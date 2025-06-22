// This script will be used to manually relay a message from L2 to L2.
// It will replicate the steps from the supersim readme guide using Go.
package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
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

	bytes32Type, _ := abi.NewType("bytes32", "", nil)
	bytes32ArrayType, _ := abi.NewType("bytes32[]", "", nil)
	uint256Type, _ := abi.NewType("uint256", "", nil)
	addressType, _ := abi.NewType("address", "", nil)
	bytesType, _ := abi.NewType("bytes", "", nil)

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

	// === Read MessageSender Address ===
	messageSenderAddress, err := getContractAddress("messagesender-902.json")
	if err != nil {
		log.Fatalf("Failed to get MessageSender address: %v", err)
	}
	fmt.Printf("Using MessageSender address: %s\n", messageSenderAddress.Hex())

	// === Step 1: Sending cross-chain message from 901 to 902 ===
	fmt.Println("\n=== Step 1: Sending cross-chain message from 901 to 902 ===")
	destChainID := big.NewInt(902)

	// Encode the call to MessageSender.sendMessages(901)
	messageSenderABI, err := abi.JSON(strings.NewReader(`[{"type":"function","name":"sendMessages","inputs":[{"name":"_destinationChainId","type":"uint256"}]}]`))
	if err != nil {
		log.Fatalf("Failed to parse MessageSender ABI: %v", err)
	}
	messagePayload, err := messageSenderABI.Pack("sendMessages", big.NewInt(901))
	if err != nil {
		log.Fatalf("Failed to pack sendMessages calldata: %v", err)
	}

	sendCalldata, err := gasTankMessengerABI.Pack("sendMessage", destChainID, messageSenderAddress, messagePayload)
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
	fmt.Printf("Got messageHash from simulation (Step 1): %x\n", messageHash)

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
	relayAccessList, err := getAccessList(identifier, sentMessagePayload)
	if err != nil {
		log.Fatalf("Failed to get access list for relay: %v", err)
	}
	fmt.Printf("Got Access List for relay with %d elements\n", len(*relayAccessList))
	for i, tuple := range *relayAccessList {
		fmt.Printf("  - Relay AL [%d] Address: %s\n", i, tuple.Address.Hex())
		for j, key := range tuple.StorageKeys {
			fmt.Printf("    - Key[%d]: %s\n", j, key.Hex())
		}
	}

	// Calculate checksum on-chain for debug
	msgHashRelay := crypto.Keccak256Hash(sentMessagePayload)
	checksumCalldataRelay, _ := crossL2InboxABI.Pack("calculateChecksum", identifier, msgHashRelay)
	checksumBytesRelay, err := client902.CallContract(context.Background(), ethereum.CallMsg{To: &crossL2InboxAddr, Data: checksumCalldataRelay}, nil)
	if err != nil {
		log.Fatalf("Failed to call calculateChecksum for relay: %v", err)
	}
	fmt.Printf(">>> Calculated Checksum for Relay (Step 5): %x\n", checksumBytesRelay)

	// === Step 6: Relay the message via GasTank on Chain 902 ===
	fmt.Println("\n=== Step 6: Relaying message via GasTank on Chain 902 ===")
	relayCalldata, err := gasTankABI.Pack("relayMessage", identifier, sentMessagePayload)
	if err != nil {
		log.Fatalf("Failed to pack relayMessage for GasTank: %v", err)
	}
	relayTx, err := sendAndWaitForTransaction(client902, big.NewInt(902), privateKey, &gasTank, big.NewInt(0), relayCalldata, *relayAccessList)
	if err != nil {
		log.Fatalf("Relay message transaction failed: %v", err)
	}
	fmt.Printf("Relay message via GasTank successful: %s\n", relayTx.TxHash.Hex())

	// --- Detailed Cost Analysis for Relay ---
	relayBlock, err := client902.HeaderByNumber(context.Background(), relayTx.BlockNumber)
	if err != nil {
		log.Printf("Warning: could not get relay block header to show basefee: %v", err)
	} else {
		fmt.Printf("Relay tx block basefee: %s wei\n", relayBlock.BaseFee.String())
	}
	fmt.Printf("Actual relay gas used: %d gas units\n", relayTx.GasUsed)
	actualRelayCost := new(big.Int).Mul(new(big.Int).SetUint64(relayTx.GasUsed), relayTx.EffectiveGasPrice)
	fmt.Printf("Actual relay transaction cost: %s wei\n", actualRelayCost.String())

	// Find and decode the cost from the event log
	var receiptLogForCost *types.Log
	for _, logEntry := range relayTx.Logs {
		if logEntry.Address == gasTank && len(logEntry.Topics) > 0 && logEntry.Topics[0] == relayedMessageGasReceiptTopic {
			receiptLogForCost = logEntry
			break
		}
	}
	if receiptLogForCost != nil {
		relayedMessageGasReceiptEventABI, err := abi.JSON(strings.NewReader(`[{"type":"event","name":"RelayedMessageGasReceipt","inputs":[{"indexed":true,"name":"messageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":false,"name":"gasCost","type":"uint256"},{"indexed":false,"name":"nestedMessageHashes","type":"bytes32[]"}],"anonymous":false}]`))
		if err != nil {
			log.Fatalf("Failed to create temporary event ABI for relay cost: %v", err)
		}
		unpackedData, err := relayedMessageGasReceiptEventABI.Events["RelayedMessageGasReceipt"].Inputs.Unpack(receiptLogForCost.Data)
		if err != nil {
			log.Fatalf("failed to unpack RelayedMessageGasReceipt event data for relay cost: %v", err)
		}
		eventRelayCost := unpackedData[0].(*big.Int)
		fmt.Printf("Relay cost from event (estimated by contract): %s wei\n", eventRelayCost.String())
	} else {
		fmt.Println("Could not find RelayedMessageGasReceipt event to log event cost.")
	}
	// --- End Cost Analysis ---

	// === Step 7: Prepare data for claim on Chain 901 ===
	fmt.Println("\n=== Step 7: Preparing data for claim on Chain 901 ===")
	// a. Find the RelayedMessageGasReceipt log from the relay transaction
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

	// b. Construct the Identifier
	block, err = client902.BlockByHash(context.Background(), relayTx.BlockHash)
	if err != nil {
		log.Fatalf("Failed to get block from hash %s: %v", relayTx.BlockHash.Hex(), err)
	}
	identifier = Identifier{
		Origin:      gasTank,
		BlockNumber: relayTx.BlockNumber,
		LogIndex:    big.NewInt(int64(receiptLog.Index)),
		Timestamp:   new(big.Int).SetUint64(block.Time()),
		ChainID:     big.NewInt(902),
	}
	fmt.Printf("Constructed Identifier: %+v\n", identifier)

	// c. Reconstruct the relayedMessageGasReceipt payload
	// We need to unpack the non-indexed fields from the log data
	relayedMessageGasReceiptEventABI, err := abi.JSON(strings.NewReader(`[{"type":"event","name":"RelayedMessageGasReceipt","inputs":[{"indexed":true,"name":"messageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":false,"name":"gasCost","type":"uint256"},{"indexed":false,"name":"nestedMessageHashes","type":"bytes32[]"}],"anonymous":false}]`))
	if err != nil {
		log.Fatalf("Failed to create temporary event ABI: %v", err)
	}

	// 1. DECODE the event fields from the log
	// Indexed fields are in Topics
	originMessageHash := receiptLog.Topics[1]
	relayer := common.BytesToAddress(receiptLog.Topics[2].Bytes())
	// Non-indexed fields are in Data
	unpackedData, err = relayedMessageGasReceiptEventABI.Events["RelayedMessageGasReceipt"].Inputs.Unpack(receiptLog.Data)
	if err != nil {
		log.Fatalf("failed to unpack RelayedMessageGasReceipt event data: %v", err)
	}
	relayCost := unpackedData[0].(*big.Int)
	destinationMessageHashes := unpackedData[1].([][32]byte)

	fmt.Printf("Decoded RelayedMessageGasReceipt: \n  OriginMessageHash (Step 7): %s\n  Relayer: %s\n  RelayCost: %s\n", originMessageHash.Hex(), relayer.Hex(), relayCost.String())

	// 2. RECONSTRUCT the payload for the claim transaction as expected by decodeGasReceiptPayload

	// Group 1 for _payload[32:128], containing fields decoded from topics
	packedGroup1, err := abi.Arguments{{Type: bytes32Type}, {Type: addressType}}.Pack(originMessageHash, relayer)
	if err != nil {
		log.Fatalf("Failed to pack group 1 for claim payload: %v", err)
	}
	// Group 2 for _payload[128:], containing fields decoded from data
	packedGroup2, err := abi.Arguments{{Type: uint256Type}, {Type: bytes32ArrayType}}.Pack(relayCost, destinationMessageHashes)
	if err != nil {
		log.Fatalf("Failed to pack group 2 for claim payload: %v", err)
	}

	// The final payload is: selector + group1 + group2
	claimPayload := append(relayedMessageGasReceiptTopic.Bytes(), packedGroup1...)
	claimPayload = append(claimPayload, packedGroup2...)

	fmt.Printf("Constructed claimPayload for claim tx: %x\n", claimPayload)

	// === Step 8: Get Access List for Claim on Chain 901 ===
	fmt.Println("\n=== Step 8: Getting Access List for Claim on Chain 901 ===")
	claimAccessList, err := getAccessList(identifier, claimPayload)
	if err != nil {
		log.Fatalf("Failed to get access list for claim: %v", err)
	}
	fmt.Printf("Got Access List for claim with %d elements\n", len(*claimAccessList))
	for i, tuple := range *claimAccessList {
		fmt.Printf("  - Claim AL [%d] Address: %s\n", i, tuple.Address.Hex())
		for j, key := range tuple.StorageKeys {
			fmt.Printf("    - Key[%d]: %s\n", j, key.Hex())
		}
	}

	// Calculate checksum on-chain for debug
	msgHashClaim := crypto.Keccak256Hash(claimPayload)
	checksumCalldataClaim, _ := crossL2InboxABI.Pack("calculateChecksum", identifier, msgHashClaim)
	checksumBytesClaim, err := client901.CallContract(context.Background(), ethereum.CallMsg{To: &crossL2InboxAddr, Data: checksumCalldataClaim}, nil)
	if err != nil {
		log.Fatalf("Failed to call calculateChecksum for claim: %v", err)
	}
	fmt.Printf(">>> Calculated Checksum for Claim (Step 8): %x\n", checksumBytesClaim)

	// === Step 8.5: Debug Balance vs Cost ===
	fmt.Println("\n=== Step 8.5: Debugging Balance vs Cost ===")
	// Get current balance on chain 901
	balanceOfCalldata, err = gasTankABI.Pack("balanceOf", fromAddress)
	if err != nil {
		log.Fatalf("Failed to pack balanceOf for debug: %v", err)
	}
	balanceBytes, err = client901.CallContract(context.Background(), ethereum.CallMsg{To: &gasTank, Data: balanceOfCalldata}, nil)
	if err != nil {
		log.Fatalf("Failed to call balanceOf for debug: %v", err)
	}
	currentBalanceOn901 := new(big.Int).SetBytes(balanceBytes)
	fmt.Printf("Current balance of gas provider on 901: %s\n", currentBalanceOn901.String())

	// Get claim overhead cost
	claimOverheadCalldata, err := gasTankABI.Pack("claimOverhead", big.NewInt(int64(len(destinationMessageHashes))))
	if err != nil {
		log.Fatalf("Failed to pack claimOverhead for debug: %v", err)
	}
	claimOverheadBytes, err := client901.CallContract(context.Background(), ethereum.CallMsg{To: &gasTank, Data: claimOverheadCalldata}, nil)
	if err != nil {
		log.Fatalf("Failed to call claimOverhead for debug: %v", err)
	}
	claimOverheadCost := new(big.Int).SetBytes(claimOverheadBytes)
	fmt.Printf("Relay cost from event: %s\n", relayCost.String())
	fmt.Printf("Calculated claimOverhead cost: %s\n", claimOverheadCost.String())

	totalCost := new(big.Int).Add(relayCost, claimOverheadCost)
	fmt.Printf("Total cost for claim: %s\n", totalCost.String())

	if currentBalanceOn901.Cmp(totalCost) < 0 {
		log.Fatalf("INSUFFICIENT BALANCE! Balance %s is less than total cost %s", currentBalanceOn901.String(), totalCost.String())
	} else {
		fmt.Println("Balance appears sufficient.")
	}

	// === Step 9: Claim the funds on Chain 901 ===
	fmt.Println("\n=== Step 9: Claiming funds on Chain 901 ===")
	claimCalldata, err := gasTankABI.Pack("claim", identifier, fromAddress, claimPayload)
	if err != nil {
		log.Fatalf("Failed to pack claim for GasTank: %v", err)
	}

	claimTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), privateKey, &gasTank, big.NewInt(0), claimCalldata, *claimAccessList)
	if err != nil {
		log.Fatalf("Claim transaction failed: %v", err)
	}
	fmt.Printf("Claim transaction successful: %s\n", claimTx.TxHash.Hex())

	// --- Detailed Cost Analysis for Claim ---
	claimBlock, err := client901.HeaderByNumber(context.Background(), claimTx.BlockNumber)
	if err != nil {
		log.Printf("Warning: could not get claim block header to show basefee: %v", err)
	} else {
		fmt.Printf("Claim tx block basefee: %s wei\n", claimBlock.BaseFee.String())
	}
	fmt.Printf("Actual claim gas used: %d gas units\n", claimTx.GasUsed)
	actualClaimCost := new(big.Int).Mul(new(big.Int).SetUint64(claimTx.GasUsed), claimTx.EffectiveGasPrice)
	fmt.Printf("Actual claim transaction cost: %s wei\n", actualClaimCost.String())

	fmt.Printf("Total script cost (deposit not included): %s wei\n", new(big.Int).Add(actualRelayCost, actualClaimCost).String())

	// Find and decode the cost from the Claimed event
	claimedEventABI, err := abi.JSON(strings.NewReader(`[{"type":"event","name":"Claimed","inputs":[{"indexed":true,"name":"originMessageHash","type":"bytes32"},{"indexed":true,"name":"relayer","type":"address"},{"indexed":true,"name":"gasProvider","type":"address"},{"indexed":false,"name":"cost","type":"uint256"}],"anonymous":false}]`))
	if err != nil {
		log.Fatalf("Failed to create temporary event ABI for Claimed event: %v", err)
	}
	claimedTopic := claimedEventABI.Events["Claimed"].ID

	var claimedLog *types.Log
	for _, logEntry := range claimTx.Logs {
		if logEntry.Address == gasTank && len(logEntry.Topics) > 0 && logEntry.Topics[0] == claimedTopic {
			claimedLog = logEntry
			break
		}
	}

	if claimedLog != nil {
		unpackedData, err := claimedEventABI.Events["Claimed"].Inputs.Unpack(claimedLog.Data)
		if err != nil {
			log.Fatalf("failed to unpack Claimed event data: %v", err)
		}
		eventClaimCost := unpackedData[0].(*big.Int)
		fmt.Printf("Claim cost from event (estimated by contract): %s wei\n", eventClaimCost.String())
	} else {
		fmt.Println("Could not find Claimed event to log event cost.")
	}
	// --- End Cost Analysis ---

	fmt.Println("\n✅ GasTank relay and claim complete!")
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

func buildRelayedMessageGasReceiptPayload(logEntry *types.Log) []byte {
	var payload []byte
	for _, topic := range logEntry.Topics {
		payload = append(payload, topic.Bytes()...)
	}
	payload = append(payload, logEntry.Data...)
	return payload
}

// Helper to read contract address from a file
func getContractAddress(filename string) (common.Address, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return common.Address{}, fmt.Errorf("failed to read %s: %w", filename, err)
	}
	var deploymentInfo struct {
		Address string `json:"address"`
	}
	if err := json.Unmarshal(data, &deploymentInfo); err != nil {
		return common.Address{}, fmt.Errorf("failed to parse JSON from %s: %w", filename, err)
	}
	return common.HexToAddress(deploymentInfo.Address), nil
}
