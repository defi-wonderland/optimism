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

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

func gasTankRelay() {
	fmt.Println("Starting GasTank end-to-end manual relay script...")

	// === Setup Clients and Signer ===
	client901, err := ethclient.Dial("http://127.0.0.1:9545")
	if err != nil {
		log.Fatalf("Failed to connect to the source chain (901): %v", err)
	}
	_, err = ethclient.Dial("http://127.0.0.1:9546")
	if err != nil {
		log.Fatalf("Failed to connect to the destination chain (902): %v", err)
	}
	privateKey, err := crypto.HexToECDSA("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
	if err != nil {
		log.Fatalf("Failed to load private key: %v", err)
	}
	fromAddress := crypto.PubkeyToAddress(*privateKey.Public().(*ecdsa.PublicKey))
	fmt.Printf("Using address: %s\n", fromAddress.Hex())

	// === Step 1: Get messageHash via eth_call and then send the transaction ===
	fmt.Println("\n=== Step 1: Sending cross-chain message from 901 to 902 ===")
	destChainID := big.NewInt(902)
	messagePayload := []byte{}
	sendCalldata, err := gasTankMessengerABI.Pack("sendMessage", destChainID, fromAddress, messagePayload)
	if err != nil {
		log.Fatalf("Failed to pack sendMessage ABI: %v", err)
	}

	// SIMULATE the transaction with eth_call to get the return value
	fmt.Println("Simulating transaction to get return value (messageHash)...")
	returnedData, err := client901.CallContract(context.Background(), ethereum.CallMsg{
		From: fromAddress,
		To:   &l2CrossDomainMessengerAddr,
		Data: sendCalldata,
	}, nil)
	if err != nil {
		log.Fatalf("Failed to simulate sendMessage call: %v", err)
	}

	if len(returnedData) != 32 {
		log.Fatalf("Expected 32 bytes of return data, but got %d", len(returnedData))
	}
	var messageHash [32]byte
	copy(messageHash[:], returnedData)
	fmt.Printf("Got messageHash from simulation: %x\n", messageHash)

	// EXECUTE the actual transaction
	fmt.Println("Executing the real transaction...")
	sendTxReceipt, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &l2CrossDomainMessengerAddr, big.NewInt(0), sendCalldata)
	if err != nil {
		log.Fatalf("Send message transaction failed: %v", err)
	}
	fmt.Printf("Real transaction successful: %s\n", sendTxReceipt.TxHash.Hex())

	// === Step 2: Authorize Claim on Gas Tank ===
	fmt.Println("\n=== Step 2: Authorizing claim on GasTank ===")
	authCalldata, err := gasTankABI.Pack("authorizeClaim", messageHash)
	if err != nil {
		log.Fatalf("Failed to pack authorizeClaim ABI: %v", err)
	}
	authTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &gasTank, big.NewInt(0), authCalldata)
	if err != nil {
		log.Fatalf("Authorize claim transaction failed: %v", err)
	}
	fmt.Printf("Authorize claim transaction successful: %s\n", authTx.TxHash.Hex())

	// === Step 3: Deposit to Gas Tank on Chain 901 (if needed) ===
	fmt.Println("\n=== Step 3: Checking balance and depositing to GasTank on Chain 901 ===")

	// Get MAX_DEPOSIT from the contract
	maxDepositCalldata, err := gasTankABI.Pack("MAX_DEPOSIT")
	if err != nil {
		log.Fatalf("Failed to pack MAX_DEPOSIT ABI: %v", err)
	}
	maxDepositBytes, err := client901.CallContract(context.Background(), ethereum.CallMsg{To: &gasTank, Data: maxDepositCalldata}, nil)
	if err != nil {
		log.Fatalf("Failed to call MAX_DEPOSIT: %v", err)
	}
	maxDeposit := new(big.Int).SetBytes(maxDepositBytes)
	fmt.Printf("MAX_DEPOSIT is: %s\n", maxDeposit.String())

	// Get current balance
	balanceOfCalldata, err := gasTankABI.Pack("balanceOf", fromAddress)
	if err != nil {
		log.Fatalf("Failed to pack balanceOf ABI: %v", err)
	}
	balanceBytes, err := client901.CallContract(context.Background(), ethereum.CallMsg{To: &gasTank, Data: balanceOfCalldata}, nil)
	if err != nil {
		log.Fatalf("Failed to call balanceOf: %v", err)
	}
	currentBalance := new(big.Int).SetBytes(balanceBytes)
	fmt.Printf("Current balance is: %s\n", currentBalance.String())

	if currentBalance.Cmp(maxDeposit) >= 0 {
		fmt.Println("Balance is full, no deposit needed.")
	} else {
		amountToDeposit := new(big.Int).Sub(maxDeposit, currentBalance)
		fmt.Printf("Depositing %s to reach max balance...\n", amountToDeposit.String())

		depositCalldata, err := gasTankABI.Pack("deposit", fromAddress)
		if err != nil {
			log.Fatalf("Failed to pack deposit ABI: %v", err)
		}
		depositTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &gasTank, amountToDeposit, depositCalldata)
		if err != nil {
			log.Fatalf("Deposit transaction failed: %v", err)
		}
		fmt.Printf("Deposit transaction successful: %s\n", depositTx.TxHash.Hex())
	}

	// === Step 4: Prepare data for relaying on Chain 902 ===
	fmt.Println("\n=== Step 4: Preparing data for relay on Chain 902 ===")
	// a. Find the SentMessage log from the original transaction
	var sentMessageLog *types.Log
	for _, logEntry := range sendTxReceipt.Logs {
		if logEntry.Address == l2CrossDomainMessengerAddr && len(logEntry.Topics) > 0 && logEntry.Topics[0] == sentMessageTopic {
			sentMessageLog = logEntry
			break
		}
	}
	if sentMessageLog == nil {
		log.Fatalf("Could not find SentMessage event in transaction logs")
	}

	// b. Construct the Identifier
	block, err := client901.BlockByHash(context.Background(), sendTxReceipt.BlockHash)
	if err != nil {
		log.Fatalf("Failed to get block from hash %s: %v", sendTxReceipt.BlockHash.Hex(), err)
	}
	identifier := Identifier{
		Origin:      l2CrossDomainMessengerAddr,
		BlockNumber: sendTxReceipt.BlockNumber,
		LogIndex:    big.NewInt(int64(sentMessageLog.Index)),
		Timestamp:   new(big.Int).SetUint64(block.Time()),
		ChainID:     big.NewInt(901),
	}
	fmt.Printf("Constructed Identifier: %+v\n", identifier)

	// c. Reconstruct the sentMessage payload
	// We need to unpack the non-indexed fields from the log data
	sentMessageEventABI, err := abi.JSON(strings.NewReader(`[{"type":"event","name":"SentMessage","inputs":[{"indexed":true,"name":"destination","type":"uint256"},{"indexed":true,"name":"target","type":"address"},{"indexed":true,"name":"messageNonce","type":"uint256"},{"indexed":false,"name":"sender","type":"address"},{"indexed":false,"name":"message","type":"bytes"}],"anonymous":false}]`))
	if err != nil {
		log.Fatalf("Failed to create temporary event ABI: %v", err)
	}

	unpackedData, err := sentMessageEventABI.Events["SentMessage"].Inputs.Unpack(sentMessageLog.Data)
	if err != nil {
		log.Fatalf("failed to unpack SentMessage event data: %v", err)
	}
	sender := unpackedData[0].(common.Address)
	message := unpackedData[1].([]byte)

	// Re-encode the data in the format expected by relayMessage's decoder
	uint256Type, err := abi.NewType("uint256", "", nil)
	if err != nil {
		log.Fatalf("Failed to create uint256 type: %v", err)
	}
	addressType, err := abi.NewType("address", "", nil)
	if err != nil {
		log.Fatalf("Failed to create address type: %v", err)
	}
	bytesType, err := abi.NewType("bytes", "", nil)
	if err != nil {
		log.Fatalf("Failed to create bytes type: %v", err)
	}

	// Encode indexed topics
	destination := new(big.Int).SetBytes(sentMessageLog.Topics[1].Bytes())
	target := common.BytesToAddress(sentMessageLog.Topics[2].Bytes())
	nonce := new(big.Int).SetBytes(sentMessageLog.Topics[3].Bytes())
	encodedTopics, err := abi.Arguments{{Type: uint256Type}, {Type: addressType}, {Type: uint256Type}}.Pack(destination, target, nonce)
	if err != nil {
		log.Fatalf("Failed to pack topics for payload: %v", err)
	}

	// Encode non-indexed data
	encodedData, err := abi.Arguments{{Type: addressType}, {Type: bytesType}}.Pack(sender, message)
	if err != nil {
		log.Fatalf("Failed to pack data for payload: %v", err)
	}

	sentMessagePayload := append(sentMessageTopic.Bytes(), encodedTopics...)
	sentMessagePayload = append(sentMessagePayload, encodedData...)
	fmt.Printf("Constructed sentMessagePayload: %x\n", sentMessagePayload)

	// === Step 5: Get Access List from Chain 902 ===
	fmt.Println("\n=== Step 5: Getting Access List from Chain 902 ===")
	accessList, err := getAccessList(identifier, sentMessagePayload)
	if err != nil {
		log.Fatalf("Failed to get access list: %v", err)
	}
	fmt.Printf("Got Access List with %d elements\n", len(*accessList))

	// === Step 6: Relay the message via GasTank on Chain 902 ===
	fmt.Println("\n=== Step 6: Relaying message via GasTank on Chain 902 ===")
	client902, err := ethclient.Dial("http://127.0.0.1:9546")
	if err != nil {
		log.Fatalf("Failed to connect to the destination chain (902): %v", err)
	}
	relayCalldata, err := gasTankABI.Pack("relayMessage", identifier, sentMessagePayload)
	if err != nil {
		log.Fatalf("Failed to pack relayMessage for GasTank: %v", err)
	}
	relayTx, err := sendAndWaitForTransaction(client902, big.NewInt(902), privateKey, &gasTank, big.NewInt(0), relayCalldata, *accessList)
	if err != nil {
		log.Fatalf("Relay message transaction failed: %v", err)
	}
	fmt.Printf("Relay message via GasTank successful: %s\n", relayTx.TxHash.Hex())

	// === Step 7: Find RelayedMessageGasReceipt log on Chain 902 ===
	fmt.Println("\n=== Step 7: Finding RelayedMessageGasReceipt log ===")
	var receiptLog *types.Log
	for _, logEntry := range relayTx.Logs {
		if logEntry.Address == gasTank && len(logEntry.Topics) > 0 && logEntry.Topics[0] == relayedMessageGasReceiptTopic {
			receiptLog = logEntry
			break
		}
	}
	if receiptLog == nil {
		log.Fatalf("Could not find RelayedMessageGasReceipt event in logs of relay transaction")
	}
	fmt.Println("Found RelayedMessageGasReceipt event log.")
	fmt.Println("\n\n✅✅✅ GasTank relay portion complete! Claim logic removed. ✅✅✅")
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
