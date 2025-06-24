// This script will be used to manually relay a message from L2 to L2.
// It will replicate the steps from the supersim readme guide using Go.
package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"

	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

func tokenRelay() {
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
	mintTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &l2TokenAddr, big.NewInt(0), mintCalldata)
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
	sendTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &superchainTokenBridgeAddr, big.NewInt(0), sendCalldata)
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
	block, err := client901.BlockByHash(context.Background(), sendTx.BlockHash)
	if err != nil {
		log.Fatalf("failed to get block by hash: %v", err)
	}
	timestamp := block.Time()
	fmt.Printf("Block number: %d, Timestamp: %d\n", sentMessageLog.BlockNumber, timestamp)

	// === Step 5: Prepare message identifier & payload ===
	fmt.Println("\n=== Step 5: Preparing identifier and payload ===")
	identifier := Identifier{
		Origin:      l2CrossDomainMessengerAddr,
		BlockNumber: new(big.Int).SetUint64(sentMessageLog.BlockNumber),
		LogIndex:    big.NewInt(int64(sentMessageLog.Index)),
		Timestamp:   new(big.Int).SetUint64(timestamp),
		ChainID:     big.NewInt(901),
	}
	var payload []byte
	for _, topic := range sentMessageLog.Topics {
		payload = append(payload, topic.Bytes()...)
	}
	payload = append(payload, sentMessageLog.Data...)
	fmt.Printf("Constructed Identifier: %+v\n", identifier)
	fmt.Printf("Successfully retrieved sent message payload: %s\n", hex.EncodeToString(payload))

	// === Step 6: Get the access list via admin RPC ===
	fmt.Println("\n=== Step 6: Retrieving access list from supersim ===")
	accessList, err := getAccessList(identifier, payload)
	if err != nil {
		log.Fatalf("Failed to get access list: %v", err)
	}
	fmt.Printf("Successfully retrieved access list with %d entries\n", len(*accessList))

	// === Step 7: Relay the message on L2 ===
	fmt.Println("\n=== Step 7: Relaying message on L2 ===")
	relayCalldata, err := crossDomainMessengerABI.Pack("relayMessage", identifier, payload)
	if err != nil {
		log.Fatalf("Failed to pack relayMessage ABI: %v", err)
	}

	relayTx, err := sendAndWaitForTransaction(client902, destChainID, privateKey, &l2CrossDomainMessengerAddr, big.NewInt(0), relayCalldata, *accessList)
	if err != nil {
		log.Fatalf("Relay transaction failed: %v", err)
	}
	fmt.Printf("Successfully relayed message on L2. Transaction hash: %s\n", relayTx.TxHash.Hex())
	fmt.Println("\n✅ Manual relay complete!")
}
