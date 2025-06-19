// This script will be used to manually relay a message from L2 to L2.
// It will replicate the steps from the supersim readme guide using Go.
package main

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"log"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

// Identifier matches the ICrossL2Inbox.Identifier struct
type Identifier struct {
	Origin      common.Address `json:"origin"`
	BlockNumber *big.Int       `json:"blockNumber"`
	LogIndex    uint32         `json:"logIndex"`
	Timestamp   uint64         `json:"timestamp"`
	ChainID     *big.Int       `json:"chainId"`
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

	// ABIs
	tokenABI, _      = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"mint","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	bridgeABI, _     = abi.JSON(strings.NewReader(`[{"inputs":[{"internalType":"address","name":"_token","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"},{"internalType":"uint256","name":"_chainId","type":"uint256"}],"name":"sendERC20","outputs":[],"stateMutability":"nonpayable","type":"function"}]`))
	messengerABI, _  = abi.JSON(strings.NewReader(`[{"inputs":[{"components":[{"internalType":"address","name":"origin","type":"address"},{"internalType":"uint256","name":"blockNumber","type":"uint256"},{"internalType":"uint256","name":"logIndex","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"},{"internalType":"uint256","name":"chainId","type":"uint256"}],"internalType":"struct ICrossL2Inbox.Identifier","name":"_id","type":"tuple"},{"internalType":"bytes","name":"_sentMessage","type":"bytes"}],"name":"relayMessage","outputs":[],"stateMutability":"payable","type":"function"}]`))
	sentMessageTopic = crypto.Keccak256Hash([]byte("SentMessage(uint256,address,uint256,address,bytes)"))
)

func main() {
	fmt.Println("Starting end-to-end manual relay script...")

	// === Setup Clients and Signer ===
	client901, err := ethclient.Dial("http://127.0.0.1:9545")
	if err != nil {
		log.Fatalf("Failed to connect to the source chain (901): %v", err)
	}
	client902, err := ethclient.Dial("http://127.0.0.1:9546")
	if err != nil {
		log.Fatalf("Failed to connect to the destination chain (902): %v", err)
	}
	privateKey, err := crypto.HexToECDSA("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
	if err != nil {
		log.Fatalf("Failed to load private key: %v", err)
	}
	fromAddress := crypto.PubkeyToAddress(*privateKey.Public().(*ecdsa.PublicKey))
	fmt.Printf("Using address: %s\n", fromAddress.Hex())

	// === Step 1: Mint tokens on Chain 901 ===
	fmt.Println("\n=== Step 1: Minting tokens on Chain 901 ===")
	mintAmount := big.NewInt(1000)
	mintCalldata, err := tokenABI.Pack("mint", fromAddress, mintAmount)
	if err != nil {
		log.Fatalf("Failed to pack mint ABI: %v", err)
	}
	mintTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &l2TokenAddr, mintCalldata)
	if err != nil {
		log.Fatalf("Mint transaction failed: %v", err)
	}
	fmt.Printf("Mint transaction successful: %s\n", mintTx.TxHash.Hex())

	// === Step 2: Send cross-chain message from 901 to 902 ===
	fmt.Println("\n=== Step 2: Sending cross-chain message from 901 to 902 ===")
	destChainID := big.NewInt(902)
	sendCalldata, err := bridgeABI.Pack("sendERC20", l2TokenAddr, fromAddress, mintAmount, destChainID)
	if err != nil {
		log.Fatalf("Failed to pack sendERC20 ABI: %v", err)
	}
	sendTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &superchainTokenBridgeAddr, sendCalldata)
	if err != nil {
		log.Fatalf("Send ERC20 transaction failed: %v", err)
	}
	fmt.Printf("Send transaction successful: %s\n", sendTx.TxHash.Hex())

	// === Step 3: Find the SentMessage log ===
	fmt.Println("\n=== Step 3: Finding the SentMessage log ===")
	var sentMessageLog types.Log
	found := false
	for _, logEntry := range sendTx.Logs {
		if logEntry.Address == l2CrossDomainMessengerAddr && len(logEntry.Topics) > 0 && logEntry.Topics[0] == sentMessageTopic {
			sentMessageLog = *logEntry
			found = true
			break
		}
	}
	if !found {
		log.Fatalf("Could not find SentMessage event in transaction logs")
	}
	fmt.Printf("Found log in transaction: %s\n", sentMessageLog.TxHash.Hex())

	// === Step 4: Retrieve block info for the log ===
	fmt.Println("\n=== Step 4: Retrieving block info ===")
	block, err := client901.BlockByNumber(context.Background(), new(big.Int).SetUint64(sentMessageLog.BlockNumber))
	if err != nil {
		log.Fatalf("Failed to retrieve block: %v", err)
	}
	timestamp := block.Time()
	fmt.Printf("Block number: %d, Timestamp: %d\n", sentMessageLog.BlockNumber, timestamp)

	// === Step 5: Prepare message identifier & payload ===
	fmt.Println("\n=== Step 5: Preparing identifier and payload ===")
	identifier := Identifier{
		Origin:      l2CrossDomainMessengerAddr,
		BlockNumber: new(big.Int).SetUint64(sentMessageLog.BlockNumber),
		LogIndex:    uint32(sentMessageLog.Index),
		Timestamp:   timestamp,
		ChainID:     big.NewInt(901),
	}
	var payload []byte
	for _, topic := range sentMessageLog.Topics {
		payload = append(payload, topic.Bytes()...)
	}
	payload = append(payload, sentMessageLog.Data...)
	fmt.Printf("Constructed Identifier: %+v\n", identifier)

	// === Step 6: Get the access list via admin RPC ===
	fmt.Println("\n=== Step 6: Retrieving access list from supersim ===")
	rpcClient, err := rpc.Dial("http://localhost:8420")
	if err != nil {
		log.Fatalf("Failed to connect to supersim admin RPC: %v", err)
	}
	req := GetAccessListForIdentifierRequest{
		Identifier: identifier,
		Payload:    "0x" + common.Bytes2Hex(payload),
	}
	var result GetAccessListResponse
	err = rpcClient.CallContext(context.Background(), &result, "admin_getAccessListForIdentifier", req)
	if err != nil {
		log.Fatalf("Failed to get access list: %v", err)
	}
	accessList := result.AccessList
	fmt.Printf("Successfully retrieved access list with %d entries\n", len(accessList))

	// === Step 7: Relay the message on Chain 902 ===
	fmt.Println("\n=== Step 7: Relaying the message on Chain 902 ===")

	// The ABI packer is strict about types. We need to pass the identifier
	// with types that match the Solidity ABI (e.g., uint256 -> *big.Int).
	abiCompatibleIdentifier := struct {
		Origin      common.Address
		BlockNumber *big.Int
		LogIndex    *big.Int
		Timestamp   *big.Int
		ChainId     *big.Int
	}{
		Origin:      identifier.Origin,
		BlockNumber: identifier.BlockNumber,
		LogIndex:    new(big.Int).SetUint64(uint64(identifier.LogIndex)),
		Timestamp:   new(big.Int).SetUint64(identifier.Timestamp),
		ChainId:     identifier.ChainID,
	}

	relayCalldata, err := messengerABI.Pack("relayMessage", abiCompatibleIdentifier, payload)
	if err != nil {
		log.Fatalf("Failed to pack relayMessage ABI: %v", err)
	}
	relayTx, err := sendAndWaitForTransaction(client902, destChainID, privateKey, &l2CrossDomainMessengerAddr, relayCalldata, accessList)
	if err != nil {
		log.Fatalf("Relay transaction failed: %v", err)
	}
	fmt.Printf("Relay transaction successful: %s\n", relayTx.TxHash.Hex())
	fmt.Println("\n✅ Manual relay complete!")
}

// sendAndWaitForTransaction is a helper to build, sign, send, and wait for a transaction
func sendAndWaitForTransaction(client *ethclient.Client, chainID *big.Int, pk *ecdsa.PrivateKey, to *common.Address, data []byte, accessList ...types.AccessList) (*types.Receipt, error) {
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
		Value:     big.NewInt(0),
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
		return nil, fmt.Errorf("failed to get transaction receipt: not found after retries")
	}

	if receipt.Status == 0 {
		return nil, fmt.Errorf("transaction failed (status 0), hash: %s", signedTx.Hash().Hex())
	}

	return receipt, nil
}
