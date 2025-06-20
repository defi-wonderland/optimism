// This file contains shared structs, variables, and helper functions for the supersim relay scripts.
package main

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
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
	gasTank                    = common.HexToAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3")

	// ABIs
	tokenABI, _            = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"mint","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	bridgeABI, _           = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_token","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"},{"internalType":"uint256","name":"_chainId","type":"uint256"}],"name":"sendERC20","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	relayMessengerABI, _   = abi.JSON(strings.NewReader(`[{"inputs":[{"components":[{"internalType":"address","name":"origin","type":"address"},{"internalType":"uint256","name":"blockNumber","type":"uint256"},{"internalType":"uint256","name":"logIndex","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"},{"internalType":"uint256","name":"chainId","type":"uint256"}],"internalType":"struct ICrossL2Inbox.Identifier","name":"_id","type":"tuple"},{"internalType":"bytes","name":"_sentMessage","type":"bytes"}],"name":"relayMessage","outputs":[],"stateMutability":"payable","type":"function"}]`))
	gasTankMessengerABI, _ = abi.JSON(strings.NewReader(`[{"type":"function","name":"sendMessage","inputs":[{"name":"_destination","type":"uint256"},{"name":"_target","type":"address"},{"name":"_message","type":"bytes"}],"outputs":[{"name":"messageHash_","type":"bytes32"}],"stateMutability":"nonpayable"},{"type":"function","name":"messageNonce","inputs":[],"outputs":[{"name":"","type":"uint256"}],"stateMutability":"view"}]`))
	gasTankABI, _          = abi.JSON(strings.NewReader(`[
		{"inputs":[{"internalType":"address","name":"_to","type":"address"}],"name":"deposit","outputs":[],"stateMutability":"payable","type":"function"},
		{"inputs":[{"internalType":"bytes32","name":"_messageHash","type":"bytes32"}],"name":"authorizeClaim","outputs":[],"stateMutability":"nonpayable","type":"function"},
		{"inputs":[],"name":"MAX_DEPOSIT","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"inputs":[{"internalType":"address","name":"gasProvider","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"inputs":[{"components":[{"internalType":"address","name":"origin","type":"address"},{"internalType":"uint256","name":"blockNumber","type":"uint256"},{"internalType":"uint256","name":"logIndex","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"},{"internalType":"uint256","name":"chainId","type":"uint256"}],"name":"_id","type":"tuple"},{"internalType":"address","name":"_gasProvider","type":"address"},{"internalType":"bytes","name":"_payload","type":"bytes"}],"name":"claim","outputs":[],"stateMutability":"nonpayable","type":"function"},
		{"inputs":[{"internalType":"uint256","name":"_numHashes","type":"uint256"}],"name":"claimOverhead","outputs":[{"internalType":"uint256","name":"overhead_","type":"uint256"}],"stateMutability":"view","type":"function"},
		{"type":"function","name":"relayMessage","inputs":[{"name":"_id","type":"tuple","components":[{"name":"origin","type":"address"},{"name":"blockNumber","type":"uint256"},{"name":"logIndex","type":"uint256"},{"name":"timestamp","type":"uint256"},{"name":"chainId","type":"uint256"}]},{"name":"_sentMessage","type":"bytes"}],"outputs":[],"stateMutability":"nonpayable"},
		{"type":"event","name":"RelayedMessageGasReceipt","inputs":[{"indexed":true,"name":"originMessageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":true,"name":"relayCost","type":"uint256"},{"indexed":false,"name":"destinationMessageHashes","type":"bytes32[]"}],"anonymous":false}
	]`))

	// Topics
	sentMessageTopic              = crypto.Keccak256Hash([]byte("SentMessage(uint256,address,uint256,address,bytes)"))
	relayedMessageGasReceiptTopic = crypto.Keccak256Hash([]byte("RelayedMessageGasReceipt(bytes32,address,uint256,bytes32[])"))
)

// sendAndWaitForTransaction is a helper to build, sign, send, and wait for a transaction
func sendAndWaitForTransaction(client *ethclient.Client, chainID *big.Int, pk *ecdsa.PrivateKey, to *common.Address, value *big.Int, data []byte, accessList ...types.AccessList) (*types.Receipt, error) {
	fromAddress := crypto.PubkeyToAddress(*pk.Public().(*ecdsa.PublicKey))
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to get nonce: %w", err)
	}
	gasTipCap, err := client.SuggestGasTipCap(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to get gas tip cap: %w", err)
	}
	latestBlock, err := client.BlockByNumber(context.Background(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get latest block: %w", err)
	}
	gasFeeCap := new(big.Int).Add(gasTipCap, new(big.Int).Mul(latestBlock.BaseFee(), big.NewInt(2)))

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

	var receipt *types.Receipt
	for i := 0; i < 5; i++ { // Retry 5 times
		receipt, err = client.TransactionReceipt(context.Background(), signedTx.Hash())
		if err == nil && receipt != nil {
			break
		}
		time.Sleep(1 * time.Second)
	}

	if err != nil {
		return nil, fmt.Errorf("failed to get transaction receipt after retries: %w", err)
	}
	if receipt == nil {
		return nil, fmt.Errorf("failed to get transaction receipt, receipt is nil")
	}
	if receipt.Status == 0 {
		return nil, fmt.Errorf("transaction failed, status 0")
	}

	return receipt, nil
}
