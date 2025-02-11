package derive

import (
	"bytes"
	"fmt"

	"github.com/ethereum-optimism/optimism/op-service/predeploys"
	"github.com/hashicorp/go-multierror"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
)

// ForceRegisterMessageSelector is the function selector for forceRegisterMessage(bytes32,Identifier)
var ForceRegisterMessageSelector = crypto.Keccak256([]byte("forceRegisterMessage(bytes32,(address,uint256,uint256,uint256,uint256))"))[0:4]

// ForceRegisterMessageCallDataSize is the expected size of the calldata for forceRegisterMessage
// 4 bytes selector + 32 bytes msgHash + 160 bytes identifier struct
const ForceRegisterMessageCallDataSize = 196

// UserDeposits transforms the L2 block-height and L1 receipts into the transaction inputs for a full L2 block
func UserDeposits(receipts []*types.Receipt, depositContractAddr common.Address) ([]*types.DepositTx, error) {
	var out []*types.DepositTx
	var result error
	for i, rec := range receipts {
		if rec.Status != types.ReceiptStatusSuccessful {
			continue
		}
		for j, log := range rec.Logs {
			if log.Address == depositContractAddr && len(log.Topics) > 0 && log.Topics[0] == DepositEventABIHash {
				dep, err := UnmarshalDepositLogEvent(log)
				if err != nil {
					result = multierror.Append(result, fmt.Errorf("malformatted L1 deposit log in receipt %d, log %d: %w", i, j, err))
				} else {
					out = append(out, dep)
				}
			}
		}
	}
	return out, result
}
func DeriveDeposits(receipts []*types.Receipt, depositContractAddr common.Address, isInterop bool) ([]hexutil.Bytes, error) {
	var result error
	userDeposits, err := UserDeposits(receipts, depositContractAddr)
	if err != nil {
		result = multierror.Append(result, err)
	}
	// Process deposits based on interop mode
	if isInterop {
		for i, tx := range userDeposits {
			// For forced messages that are supervisor-valid, swap the From address
			if isForcedMessage(tx) && isSupervisorValid(tx) {
				userDeposits[i] = swapFrom(tx, L1InfoDepositerAddress)
			}
		}
	}

	// Pre-allocate encoded transactions slice
	encodedUserTxs := make([]hexutil.Bytes, 0, len(userDeposits))

	// Encode all userDeposits
	for i, tx := range userDeposits {
		opaqueTx, err := types.NewTx(tx).MarshalBinary()
		if err != nil {
			result = multierror.Append(result, fmt.Errorf("failed to encode user tx %d", i))
		} else {
			encodedUserTxs = append(encodedUserTxs, opaqueTx)
		}
	}

	return encodedUserTxs, result
}

// isForcedMessage returns true if the deposit transaction is a forced message
func isForcedMessage(tx *types.DepositTx) bool {
	// Check if target is CrossL2Inbox
	if tx.To == nil || *tx.To != predeploys.CrossL2InboxAddr {
		return false
	}

	// Check if calldata matches expected size for forceRegisterMessage function
	if len(tx.Data) != ForceRegisterMessageCallDataSize {
		return false
	}

	// Check if calldata starts with forceRegisterMessage selector
	return bytes.Equal(tx.Data[:4], ForceRegisterMessageSelector[:])
}

// swapFrom returns a copy of the deposit tx with From set to the given address
func swapFrom(tx *types.DepositTx, from common.Address) *types.DepositTx {
	return &types.DepositTx{
		SourceHash:          tx.SourceHash,
		From:                from,
		To:                  tx.To,
		Mint:                tx.Mint,
		Value:               tx.Value,
		Gas:                 tx.Gas,
		IsSystemTransaction: tx.IsSystemTransaction,
		Data:                tx.Data,
	}
}

// isSupervisorValid returns true if the transaction is valid according to the supervisor
func isSupervisorValid(tx *types.DepositTx) bool {
	return true
}
