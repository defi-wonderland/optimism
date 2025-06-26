// This file contains shared structs, variables, and helper functions for the supersim relay scripts.
package main

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

// Identifier matches the ICrossL2Inbox.Identifier struct
type Identifier struct {
	Origin      common.Address `json:"origin" abi:"origin"`
	BlockNumber *big.Int       `json:"blockNumber" abi:"blockNumber"`
	LogIndex    *big.Int       `json:"logIndex" abi:"logIndex"`
	Timestamp   *big.Int       `json:"timestamp" abi:"timestamp"`
	ChainID     *big.Int       `json:"chainId" abi:"chainId"`
}

// GetAccessListForIdentifierRequest mirrors the structure for the admin RPC call
type GetAccessListForIdentifierRequest struct {
	Identifier
	Payload string `json:"payload"`
}

// AccessList is part of the response
type AccessList struct {
	Address     common.Address `json:"address"`
	StorageKeys []common.Hash  `json:"storageKeys"`
}

// GetAccessListResponse mirrors the structure of the admin RPC response
type GetAccessListResponse struct {
	AccessList types.AccessList `json:"accessList"`
}

var (
	// Contract Addresses
	l2TokenAddr                = common.HexToAddress("0x420beeF000000000000000000000000000000001")
	superchainTokenBridgeAddr  = common.HexToAddress("0x4200000000000000000000000000000000000028")
	l2CrossDomainMessengerAddr = common.HexToAddress("0x4200000000000000000000000000000000000023")
	crossL2InboxAddr           = common.HexToAddress("0x4200000000000000000000000000000000000022")

	// ABIs
	tokenABI, _                = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"mint","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	bridgeABI, _               = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_token","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"},{"internalType":"uint256","name":"_chainId","type":"uint256"}],"name":"sendERC20","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	crossL2InboxABI, _         = abi.JSON(strings.NewReader(`[{"inputs":[{"components":[{"internalType":"address","name":"origin","type":"address"},{"internalType":"uint256","name":"blockNumber","type":"uint256"},{"internalType":"uint256","name":"logIndex","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"},{"internalType":"uint256","name":"chainId","type":"uint256"}],"name":"_id","type":"tuple"},{"internalType":"bytes32","name":"_msgHash","type":"bytes32"}],"name":"calculateChecksum","outputs":[{"internalType":"bytes32","name":"checksum_","type":"bytes32"}],"stateMutability":"pure","type":"function"}]`))
	crossDomainMessengerABI, _ = abi.JSON(strings.NewReader(`[{"type":"function","name":"crossDomainMessageContext","inputs":[],"outputs":[{"name":"sender_","type":"address","internalType":"address"},{"name":"source_","type":"uint256","internalType":"uint256"}],"stateMutability":"view"},{"type":"function","name":"crossDomainMessageSender","inputs":[],"outputs":[{"name":"sender_","type":"address","internalType":"address"}],"stateMutability":"view"},{"type":"function","name":"crossDomainMessageSource","inputs":[],"outputs":[{"name":"source_","type":"uint256","internalType":"uint256"}],"stateMutability":"view"},{"type":"function","name":"messageNonce","inputs":[],"outputs":[{"name":"","type":"uint256","internalType":"uint256"}],"stateMutability":"view"},{"type":"function","name":"messageVersion","inputs":[],"outputs":[{"name":"","type":"uint16","internalType":"uint16"}],"stateMutability":"view"},{"type":"function","name":"relayMessage","inputs":[{"name":"_id","type":"tuple","internalType":"struct Identifier","components":[{"name":"origin","type":"address","internalType":"address"},{"name":"blockNumber","type":"uint256","internalType":"uint256"},{"name":"logIndex","type":"uint256","internalType":"uint256"},{"name":"timestamp","type":"uint256","internalType":"uint256"},{"name":"chainId","type":"uint256","internalType":"uint256"}]},{"name":"_sentMessage","type":"bytes","internalType":"bytes"}],"outputs":[{"name":"returnData_","type":"bytes","internalType":"bytes"}],"stateMutability":"payable"},{"type":"function","name":"resendMessage","inputs":[{"name":"_destination","type":"uint256","internalType":"uint256"},{"name":"_nonce","type":"uint256","internalType":"uint256"},{"name":"_sender","type":"address","internalType":"address"},{"name":"_target","type":"address","internalType":"address"},{"name":"_message","type":"bytes","internalType":"bytes"}],"outputs":[{"name":"messageHash_","type":"bytes32","internalType":"bytes32"}],"stateMutability":"nonpayable"},{"type":"function","name":"sendMessage","inputs":[{"name":"_destination","type":"uint256","internalType":"uint256"},{"name":"_target","type":"address","internalType":"address"},{"name":"_message","type":"bytes","internalType":"bytes"}],"outputs":[{"name":"messageHash_","type":"bytes32","internalType":"bytes32"}],"stateMutability":"nonpayable"},{"type":"function","name":"sentMessages","inputs":[{"name":"","type":"uint256","internalType":"uint256"}],"outputs":[{"name":"","type":"bytes32","internalType":"bytes32"}],"stateMutability":"view"},{"type":"function","name":"successfulMessages","inputs":[{"name":"","type":"bytes32","internalType":"bytes32"}],"outputs":[{"name":"","type":"bool","internalType":"bool"}],"stateMutability":"view"},{"type":"function","name":"version","inputs":[],"outputs":[{"name":"","type":"string","internalType":"string"}],"stateMutability":"view"},{"type":"event","name":"RelayedMessage","inputs":[{"name":"source","type":"uint256","indexed":true,"internalType":"uint256"},{"name":"messageNonce","type":"uint256","indexed":true,"internalType":"uint256"},{"name":"messageHash","type":"bytes32","indexed":true,"internalType":"bytes32"},{"name":"returnDataHash","type":"bytes32","indexed":false,"internalType":"bytes32"}],"anonymous":false},{"type":"event","name":"SentMessage","inputs":[{"name":"destination","type":"uint256","indexed":true,"internalType":"uint256"},{"name":"target","type":"address","indexed":true,"internalType":"address"},{"name":"messageNonce","type":"uint256","indexed":true,"internalType":"uint256"},{"name":"sender","type":"address","indexed":false,"internalType":"address"},{"name":"message","type":"bytes","indexed":false,"internalType":"bytes"}],"anonymous":false},{"type":"error","name":"EventPayloadNotSentMessage","inputs":[]},{"type":"error","name":"IdOriginNotL2ToL2CrossDomainMessenger","inputs":[]},{"type":"error","name":"InvalidMessage","inputs":[]},{"type":"error","name":"MessageAlreadyRelayed","inputs":[]},{"type":"error","name":"MessageDestinationNotRelayChain","inputs":[]},{"type":"error","name":"MessageDestinationSameChain","inputs":[]},{"type":"error","name":"MessageTargetL2ToL2CrossDomainMessenger","inputs":[]},{"type":"error","name":"NotEntered","inputs":[]},{"type":"error","name":"ReentrantCall","inputs":[]}]`))
	gasTankABI, _              = abi.JSON(strings.NewReader(`[
		{"inputs":[{"internalType":"address","name":"_to","type":"address"}],"name":"deposit","outputs":[],"stateMutability":"payable","type":"function"},
		{"inputs":[{"internalType":"bytes32","name":"_messageHash","type":"bytes32"}],"name":"authorizeClaim","outputs":[],"stateMutability":"nonpayable","type":"function"},
		{"inputs":[],"name":"MAX_DEPOSIT","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"inputs":[{"internalType":"address","name":"gasProvider","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"inputs":[{"components":[{"internalType":"address","name":"origin","type":"address"},{"internalType":"uint256","name":"blockNumber","type":"uint256"},{"internalType":"uint256","name":"logIndex","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"},{"internalType":"uint256","name":"chainId","type":"uint256"}],"name":"_id","type":"tuple"},{"internalType":"address","name":"_gasProvider","type":"address"},{"internalType":"bytes","name":"_payload","type":"bytes"}],"name":"claim","outputs":[],"stateMutability":"nonpayable","type":"function"},
		{"inputs":[{"internalType":"uint256","name":"_numHashes","type":"uint256"}],"name":"claimOverhead","outputs":[{"internalType":"uint256","name":"overhead_","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"type":"function","name":"relayMessage","inputs":[{"name":"_id","type":"tuple","components":[{"name":"origin","type":"address"},{"name":"blockNumber","type":"uint256"},{"name":"logIndex","type":"uint256"},{"name":"timestamp","type":"uint256"},{"name":"chainId","type":"uint256"}]},{"name":"_sentMessage","type":"bytes"}],"outputs":[],"stateMutability":"nonpayable"},
		{"type":"event","name":"RelayedMessageGasReceipt","inputs":[{"indexed":true,"name":"originMessageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":true,"name":"relayCost","type":"uint256"},{"indexed":false,"name":"destinationMessageHashes","type":"bytes32[]"}],"anonymous":false}
	]`))
	messageSenderABI, _                 = abi.JSON(strings.NewReader(`[{"type":"function","name":"sendMessages","inputs":[{"name":"_destinationChainId","type":"uint256"},{"name":"_numMessages","type":"uint256"}]}]`))
	sentMessageEventABI, _              = abi.JSON(strings.NewReader(`[{"type":"event","name":"SentMessage","inputs":[{"indexed":true,"name":"destination","type":"uint256"},{"indexed":true,"name":"target","type":"address"},{"indexed":true,"name":"messageNonce","type":"uint256"},{"indexed":false,"name":"sender","type":"address"},{"indexed":false,"name":"message","type":"bytes"}],"anonymous":false}]`))
	relayedMessageGasReceiptEventABI, _ = abi.JSON(strings.NewReader(`[{"type":"event","name":"RelayedMessageGasReceipt","inputs":[{"indexed":true,"name":"messageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":false,"name":"gasCost","type":"uint256"},{"indexed":false,"name":"nestedMessageHashes","type":"bytes32[]"}],"anonymous":false}]`))
	claimedEventABI, _                  = abi.JSON(strings.NewReader(`[{"type":"event","name":"Claimed","inputs":[{"indexed":true,"name":"originMessageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":true,"name":"gasProvider","type":"address"},{"indexed":false,"name":"claimer","type":"address"},{"indexed":false,"name":"relayCost","type":"uint256"},{"indexed":false,"name":"claimCost","type":"uint256"}],"anonymous":false}]`))

	// Events Signatures
	sentMessageTopic              = crypto.Keccak256Hash([]byte("SentMessage(uint256,address,uint256,address,bytes)"))
	relayedMessageGasReceiptTopic = crypto.Keccak256Hash([]byte("RelayedMessageGasReceipt(bytes32,address,uint256,bytes32[])"))

	// Event Types
	bytes32Type, _      = abi.NewType("bytes32", "", nil)
	bytes32ArrayType, _ = abi.NewType("bytes32[]", "", nil)
	uint256Type, _      = abi.NewType("uint256", "", nil)
	addressType, _      = abi.NewType("address", "", nil)
	bytesType, _        = abi.NewType("bytes", "", nil)
)

// sendAndWaitForTransaction is a helper to build, sign, send, and wait for a transaction
func sendAndWaitForTransaction(client *ethclient.Client, chainID *big.Int, pk *ecdsa.PrivateKey, to *common.Address, value *big.Int, data []byte, accessList ...types.AccessList) (*types.Receipt, error) {
	fromAddress := crypto.PubkeyToAddress(*pk.Public().(*ecdsa.PublicKey))
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to get nonce: %w", err)
	}

	latestBlock, err := client.BlockByNumber(context.Background(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get latest block: %w", err)
	}
	gasFeeCap := new(big.Int).Mul(latestBlock.BaseFee(), big.NewInt(2))

	// For this test, we want to align with the contract's cost calculation, which only uses basefee.
	// By setting the tip to 0, we ensure the relayer is only paying the base network fee.
	gasTipCap := big.NewInt(0)

	txData := &types.DynamicFeeTx{
		ChainID:   chainID,
		Nonce:     nonce,
		GasFeeCap: gasFeeCap,
		GasTipCap: gasTipCap,
		To:        to,
		Value:     value,
		Data:      data,
		Gas:       2000000,
	}
	if len(accessList) > 0 {
		txData.AccessList = accessList[0]
	}

	tx := types.NewTx(txData)
	signedTx, err := types.SignTx(tx, types.NewLondonSigner(chainID), pk)
	if err != nil {
		return nil, fmt.Errorf("failed to sign transaction: %w", err)
	}

	err = client.SendTransaction(context.Background(), signedTx)
	if err != nil {
		return nil, fmt.Errorf("failed to send transaction: %w", err)
	}

	receipt, err := bind.WaitMined(context.Background(), client, signedTx)
	if err != nil {
		// If WaitMined returns a receipt, it means the transaction was mined but reverted.
		// We can use the receipt to get more information.
		if receipt != nil {
			// Proceed to the status check below.
		} else {
			return nil, fmt.Errorf("failed to wait for transaction to be mined: %w", err)
		}
	}

	if receipt.Status == 0 {
		// Transaction failed, try to get the revert reason by re-executing the transaction as a call.
		fromAddress := crypto.PubkeyToAddress(*pk.Public().(*ecdsa.PublicKey))
		callMsg := ethereum.CallMsg{
			From:  fromAddress,
			To:    to,
			Value: value,
			Data:  data,
		}

		// Re-execute the transaction call at the block it failed in to get the revert reason.
		_, callErr := client.CallContract(context.Background(), callMsg, receipt.BlockNumber)

		// The error from CallContract should contain the revert reason.
		if callErr != nil {
			return nil, fmt.Errorf("transaction failed with status 0. Revert reason: %v", callErr)
		}

		return nil, fmt.Errorf("transaction failed with status 0 (revert reason not found)")
	}

	return receipt, nil
}

func getAccessList(id Identifier, payload []byte) (*types.AccessList, error) {
	// As pointed out, we should use an admin RPC client, similar to relay.go
	// The relay.go script connects to port 8420 for the supersim admin rpc.
	rpcClient, err := rpc.Dial("http://localhost:8420")
	if err != nil {
		return nil, fmt.Errorf("failed to connect to supersim admin RPC: %w", err)
	}
	defer rpcClient.Close()

	req := GetAccessListForIdentifierRequest{
		Identifier: id,
		Payload:    "0x" + common.Bytes2Hex(payload),
	}

	var result GetAccessListResponse
	err = rpcClient.CallContext(context.Background(), &result, "admin_getAccessListForIdentifier", req)
	if err != nil {
		return nil, fmt.Errorf("failed to get access list via admin_getAccessListForIdentifier: %w", err)
	}

	return &result.AccessList, nil
}
