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
	"path/filepath"
	"runtime"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type SupersimContracts struct {
	GasTank901       string `json:"gasTank901"`
	GasTank902       string `json:"gasTank902"`
	MessageSender902 string `json:"messageSender902"`
}

// GasDeltaResult holds the gas delta for a single run
type GasDeltaResult struct {
	Relay *big.Int `json:"relay"`
	Claim *big.Int `json:"claim"`
}

func logIf(verbose bool, a ...interface{}) {
	if verbose {
		fmt.Println(a...)
	}
}

func logfIf(verbose bool, format string, a ...interface{}) {
	if verbose {
		fmt.Printf(format, a...)
	}
}

func runGasAnalysis() {
	results := make(map[int]*GasDeltaResult)
	var keys []int

	for i := 0; i <= 60; i += 1 {
		logfIf(true, "\n--- Running for %d nested messages ---\n", i)
		relayGasDelta, claimGasDelta, err := gasTankRelay(int64(i), false)
		if err != nil {
			log.Printf("Failed to run for %d nested messages: %v", i, err)
			continue
		}
		results[i] = &GasDeltaResult{
			Relay: relayGasDelta,
			Claim: claimGasDelta,
		}
		keys = append(keys, i)
	}

	// Get the path of the currently running file
	_, b, _, _ := runtime.Caller(0)
	basepath := filepath.Dir(b)
	filePath := filepath.Join(basepath, "gas_analysis.json")

	// Create ordered JSON manually to ensure numeric ordering
	var jsonBuilder strings.Builder
	jsonBuilder.WriteString("{\n")

	for idx, key := range keys {
		result := results[key]
		jsonBuilder.WriteString(fmt.Sprintf(`  "%d": {`, key))
		jsonBuilder.WriteString(fmt.Sprintf(`
    "relay": %s,
    "claim": %s
  }`, result.Relay.String(), result.Claim.String()))

		if idx < len(keys)-1 {
			jsonBuilder.WriteString(",")
		}
		jsonBuilder.WriteString("\n")
	}
	jsonBuilder.WriteString("}")

	err := os.WriteFile(filePath, []byte(jsonBuilder.String()), 0644)
	if err != nil {
		log.Fatalf("Failed to write JSON to file: %v", err)
	}

	fmt.Printf("\n✅ Gas analysis complete. Results saved to %s\n", filePath)
}

func gasTankRelay(numNestedMessages int64, verbose bool) (*big.Int, *big.Int, error) {
	logIf(verbose, "Starting GasTank end-to-end manual relay script...")

	// === Setup Clients and Signer ===
	client901, err := ethclient.Dial("http://127.0.0.1:9545")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to connect to the source chain (901): %w", err)
	}
	client902, err := ethclient.Dial("http://127.0.0.1:9546")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to connect to the destination chain (902): %w", err)
	}
	// This will be the gas provider, funding the operation.
	gasProviderPrivateKey, err := crypto.HexToECDSA("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load gas provider private key: %w", err)
	}
	gasProviderAddress := crypto.PubkeyToAddress(*gasProviderPrivateKey.Public().(*ecdsa.PublicKey))
	logfIf(verbose, "Using Gas Provider address (Account 0): %s\n", gasProviderAddress.Hex())

	// This will be the relayer, executing the cross-chain part.
	relayerPrivateKey, err := crypto.HexToECDSA("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load relayer private key: %w", err)
	}
	relayerAddress := crypto.PubkeyToAddress(*relayerPrivateKey.Public().(*ecdsa.PublicKey))
	logfIf(verbose, "Using Relayer address (Account 1):      %s\n", relayerAddress.Hex())

	// === Read Deployed Contract Addresses ===
	// Get the path of the currently running file
	_, b, _, _ := runtime.Caller(0)
	basepath := filepath.Dir(b)
	contractsFilePath := filepath.Join(basepath, "supersim-contracts.json")

	contractsFile, err := os.ReadFile(contractsFilePath)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read supersim-contracts.json file. Please run `forge script test/supersim/SetupSupersim.s.sol --broadcast` first. Error: %w", err)
	}

	var contracts SupersimContracts
	if err := json.Unmarshal(contractsFile, &contracts); err != nil {
		return nil, nil, fmt.Errorf("failed to parse supersim-contracts.json: %w", err)
	}

	gasTank901Address := common.HexToAddress(contracts.GasTank901)
	gasTank902Address := common.HexToAddress(contracts.GasTank902)
	messageSenderAddress := common.HexToAddress(contracts.MessageSender902)

	logfIf(verbose, "Using GasTank (901) address:         %s\n", gasTank901Address.Hex())
	logfIf(verbose, "Using GasTank (902) address:         %s\n", gasTank902Address.Hex())
	logfIf(verbose, "Using MessageSender (902) address:   %s\n", messageSenderAddress.Hex())

	// === Step 1: Sending cross-chain message from 901 to 902 ===
	logIf(verbose, "\n=== Step 1: Sending cross-chain message from 901 to 902 (as Gas Provider) ===")
	destChainID := big.NewInt(902)

	// Encode the call to MessageSender.sendMessages(901)
	messagePayload, err := messageSenderABI.Pack("sendMessages", big.NewInt(901), big.NewInt(numNestedMessages))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack sendMessages calldata: %w", err)
	}

	sendCalldata, err := crossDomainMessengerABI.Pack("sendMessage", destChainID, messageSenderAddress, messagePayload)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack sendMessage ABI: %w", err)
	}

	// SIMULATE the transaction with eth_call to get the return value
	logIf(verbose, "Simulating transaction to get return value (messageHash)...")
	returnedData, err := client901.CallContract(context.Background(), ethereum.CallMsg{
		From: gasProviderAddress,
		To:   &l2CrossDomainMessengerAddr,
		Data: sendCalldata,
	}, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to simulate sendMessage call: %w", err)
	}

	if len(returnedData) != 32 {
		return nil, nil, fmt.Errorf("expected 32 bytes of return data, but got %d", len(returnedData))
	}
	var messageHash [32]byte
	copy(messageHash[:], returnedData)
	logfIf(verbose, "Got messageHash from simulation (Step 1): %x\n", messageHash)

	// EXECUTE the actual transaction
	logIf(verbose, "Executing the real transaction...")
	sendTxReceipt, err := sendAndWaitForTransaction(client901, big.NewInt(901), gasProviderPrivateKey, &l2CrossDomainMessengerAddr, big.NewInt(0), sendCalldata)
	if err != nil {
		return nil, nil, fmt.Errorf("send message transaction failed: %w", err)
	}
	logfIf(verbose, "Real transaction successful: %s\n", sendTxReceipt.TxHash.Hex())

	// === Step 2: Authorize Claim on Gas Tank ===
	logIf(verbose, "\n=== Step 2: Authorizing claim on GasTank (as Gas Provider) ===")
	authCalldata, err := gasTankABI.Pack("authorizeClaim", messageHash)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack authorizeClaim ABI: %w", err)
	}
	authTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), gasProviderPrivateKey, &gasTank901Address, big.NewInt(0), authCalldata)
	if err != nil {
		return nil, nil, fmt.Errorf("authorize claim transaction failed: %w", err)
	}
	logfIf(verbose, "Authorize claim transaction successful: %s\n", authTx.TxHash.Hex())

	// === Step 3: Deposit to Gas Tank on Chain 901 (if needed) ===
	logIf(verbose, "\n=== Step 3: Checking balance and depositing to GasTank on Chain 901 (as Gas Provider) ===")

	// Get MAX_DEPOSIT from the contract
	maxDepositCalldata, err := gasTankABI.Pack("MAX_DEPOSIT")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack MAX_DEPOSIT ABI: %w", err)
	}
	maxDepositBytes, err := client901.CallContract(context.Background(), ethereum.CallMsg{To: &gasTank901Address, Data: maxDepositCalldata}, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to call MAX_DEPOSIT: %w", err)
	}
	maxDeposit := new(big.Int).SetBytes(maxDepositBytes)
	logfIf(verbose, "MAX_DEPOSIT is: %s\n", maxDeposit.String())

	// Get current balance
	currentBalance, err := getCurrentGasProviderBalance(client901, gasProviderAddress, gasTank901Address)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get current balance: %w", err)
	}
	logfIf(verbose, "Current balance is: %s\n", currentBalance.String())

	if currentBalance.Cmp(maxDeposit) < 0 {
		amountToDeposit := new(big.Int).Sub(maxDeposit, currentBalance)
		logfIf(verbose, "Depositing %s to reach max balance...\n", amountToDeposit.String())

		depositCalldata, err := gasTankABI.Pack("deposit", gasProviderAddress)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to pack deposit ABI: %w", err)
		}
		depositTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), gasProviderPrivateKey, &gasTank901Address, amountToDeposit, depositCalldata)
		if err != nil {
			return nil, nil, fmt.Errorf("deposit transaction failed: %w", err)
		}
		logfIf(verbose, "Deposit transaction successful: %s\n", depositTx.TxHash.Hex())
	} else {
		logIf(verbose, "Balance is full, no deposit needed.")
	}

	// === Step 4: Prepare data for relaying on Chain 902 ===
	logIf(verbose, "\n=== Step 4: Preparing data for relay on Chain 902 ===")
	// a. Find the SentMessage log from the original transaction
	var sentMessageLog *types.Log
	for _, logEntry := range sendTxReceipt.Logs {
		if logEntry.Address == l2CrossDomainMessengerAddr && len(logEntry.Topics) > 0 && logEntry.Topics[0] == sentMessageTopic {
			sentMessageLog = logEntry
			break
		}
	}
	if sentMessageLog == nil {
		return nil, nil, fmt.Errorf("could not find SentMessage event in transaction logs")
	}

	// b. Construct the Identifier
	block, err := client901.BlockByHash(context.Background(), sendTxReceipt.BlockHash)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get block from hash %s: %w", sendTxReceipt.BlockHash.Hex(), err)
	}
	identifier := Identifier{
		Origin:      l2CrossDomainMessengerAddr,
		BlockNumber: sendTxReceipt.BlockNumber,
		LogIndex:    big.NewInt(int64(sentMessageLog.Index)),
		Timestamp:   new(big.Int).SetUint64(block.Time()),
		ChainID:     big.NewInt(901),
	}
	logfIf(verbose, "Constructed Identifier: %+v\n", identifier)

	// c. Reconstruct the sentMessage payload
	// We need to unpack the non-indexed fields from the log data
	unpackedData, err := sentMessageEventABI.Events["SentMessage"].Inputs.Unpack(sentMessageLog.Data)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to unpack SentMessage event data: %w", err)
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
		return nil, nil, fmt.Errorf("failed to pack topics for payload: %w", err)
	}

	// Encode non-indexed data
	encodedData, err := abi.Arguments{{Type: addressType}, {Type: bytesType}}.Pack(sender, message)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack data for payload: %w", err)
	}

	sentMessagePayload := append(sentMessageTopic.Bytes(), encodedTopics...)
	sentMessagePayload = append(sentMessagePayload, encodedData...)
	logfIf(verbose, "Constructed sentMessagePayload: %x\n", sentMessagePayload)

	// === Step 5: Get Access List from Chain 902 ===
	logIf(verbose, "\n=== Step 5: Getting Access List from Chain 902 ===")
	relayAccessList, err := getAccessList(identifier, sentMessagePayload)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get access list for relay: %w", err)
	}
	logfIf(verbose, "Got Access List for relay with %d elements\n", len(*relayAccessList))
	if verbose {
		for i, tuple := range *relayAccessList {
			logfIf(verbose, "  - Relay AL [%d] Address: %s\n", i, tuple.Address.Hex())
			for j, key := range tuple.StorageKeys {
				logfIf(verbose, "    - Key[%d]: %s\n", j, key.Hex())
			}
		}
	}

	// === Step 6: Relay the message via GasTank on Chain 902 ===
	logIf(verbose, "\n=== Step 6: Relaying message via GasTank on Chain 902 (as Relayer) ===")
	relayCalldata, err := gasTankABI.Pack("relayMessage", identifier, sentMessagePayload)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack relayMessage for GasTank: %w", err)
	}
	relayTx, err := sendAndWaitForTransaction(client902, big.NewInt(902), relayerPrivateKey, &gasTank902Address, big.NewInt(0), relayCalldata, *relayAccessList)
	if err != nil {
		return nil, nil, fmt.Errorf("relay message transaction failed: %w", err)
	}
	logfIf(verbose, "Relay message via GasTank successful: %s\n", relayTx.TxHash.Hex())

	// Capture relay cost details for final analysis
	relayBlock, err := client902.HeaderByNumber(context.Background(), relayTx.BlockNumber)
	if err != nil {
		log.Printf("Warning: could not get relay block header for final analysis: %v", err)
	}
	actualRelayCost := new(big.Int).Mul(new(big.Int).SetUint64(relayTx.GasUsed), relayTx.EffectiveGasPrice)

	var eventRelayCost *big.Int
	var receiptLogForCost *types.Log
	for _, logEntry := range relayTx.Logs {
		if logEntry.Address == gasTank902Address && len(logEntry.Topics) > 0 && logEntry.Topics[0] == relayedMessageGasReceiptTopic {
			receiptLogForCost = logEntry
			break
		}
	}
	if receiptLogForCost != nil {
		unpackedData, err := relayedMessageGasReceiptEventABI.Events["RelayedMessageGasReceipt"].Inputs.Unpack(receiptLogForCost.Data)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to unpack RelayedMessageGasReceipt event data for relay cost: %w", err)
		}
		eventRelayCost = unpackedData[0].(*big.Int)
	} else {
		// This is critical for the rest of the script.
		return nil, nil, fmt.Errorf("could not find RelayedMessageGasReceipt event to get relay cost from event")
	}

	// === Step 7: Prepare data for claim on Chain 901 ===
	logIf(verbose, "\n=== Step 7: Preparing data for claim on Chain 901 ===")
	// a. Find the RelayedMessageGasReceipt log from the relay transaction
	var receiptLog *types.Log
	for _, logEntry := range relayTx.Logs {
		if logEntry.Address == gasTank902Address && len(logEntry.Topics) > 0 && logEntry.Topics[0] == relayedMessageGasReceiptTopic {
			receiptLog = logEntry
			break
		}
	}
	if receiptLog == nil {
		return nil, nil, fmt.Errorf("could not find RelayedMessageGasReceipt event in logs of relay transaction")
	}
	logIf(verbose, "Found RelayedMessageGasReceipt event log.")

	// b. Construct the Identifier
	block, err = client902.BlockByHash(context.Background(), relayTx.BlockHash)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get block from hash %s: %w", relayTx.BlockHash.Hex(), err)
	}
	identifier = Identifier{
		Origin:      gasTank902Address,
		BlockNumber: relayTx.BlockNumber,
		LogIndex:    big.NewInt(int64(receiptLog.Index)),
		Timestamp:   new(big.Int).SetUint64(block.Time()),
		ChainID:     big.NewInt(902),
	}
	logfIf(verbose, "Constructed Identifier: %+v\n", identifier)

	// c. Reconstruct the relayedMessageGasReceipt payload
	// We need to unpack the non-indexed fields from the log data

	// 1. DECODE the event fields from the log
	// Indexed fields are in Topics
	originMessageHash := receiptLog.Topics[1]
	relayerFromEvent := common.BytesToAddress(receiptLog.Topics[2].Bytes())
	// Non-indexed fields are in Data
	unpackedData, err = relayedMessageGasReceiptEventABI.Events["RelayedMessageGasReceipt"].Inputs.Unpack(receiptLog.Data)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to unpack RelayedMessageGasReceipt event data: %w", err)
	}
	relayCost := unpackedData[0].(*big.Int)
	destinationMessageHashes := unpackedData[1].([][32]byte)

	if relayerFromEvent != relayerAddress {
		return nil, nil, fmt.Errorf("relayer from event (%s) does not match expected relayer address (%s)", relayerFromEvent.Hex(), relayerAddress.Hex())
	}

	logfIf(verbose, "Decoded RelayedMessageGasReceipt: \n  OriginMessageHash (Step 7): %s\n  Relayer: %s\n  RelayCost: %s\n", originMessageHash.Hex(), relayerFromEvent.Hex(), relayCost.String())

	// 2. RECONSTRUCT the payload for the claim transaction as expected by decodeGasReceiptPayload

	// Group 1 for _payload[32:128], containing fields decoded from topics
	packedGroup1, err := abi.Arguments{{Type: bytes32Type}, {Type: addressType}}.Pack(originMessageHash, relayerFromEvent)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack group 1 for claim payload: %w", err)
	}
	// Group 2 for _payload[128:], containing fields decoded from data
	packedGroup2, err := abi.Arguments{{Type: uint256Type}, {Type: bytes32ArrayType}}.Pack(relayCost, destinationMessageHashes)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack group 2 for claim payload: %w", err)
	}

	// The final payload is: selector + group1 + group2
	claimPayload := append(relayedMessageGasReceiptTopic.Bytes(), packedGroup1...)
	claimPayload = append(claimPayload, packedGroup2...)

	logfIf(verbose, "Constructed claimPayload for claim tx: %x\n", claimPayload)

	// === Step 8: Get Access List for Claim on Chain 901 ===
	logIf(verbose, "\n=== Step 8: Getting Access List for Claim on Chain 901 ===")
	claimAccessList, err := getAccessList(identifier, claimPayload)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get access list for claim: %w", err)
	}
	logfIf(verbose, "Got Access List for claim with %d elements\n", len(*claimAccessList))
	if verbose {
		for i, tuple := range *claimAccessList {
			logfIf(verbose, "  - Claim AL [%d] Address: %s\n", i, tuple.Address.Hex())
			for j, key := range tuple.StorageKeys {
				logfIf(verbose, "    - Key[%d]: %s\n", j, key.Hex())
			}
		}
	}

	// === Step 9: Claiming funds on Chain 901 (as Relayer) ===
	logIf(verbose, "\n=== Step 9: Claiming funds on Chain 901 (as Relayer) ===")
	claimCalldata, err := gasTankABI.Pack("claim", identifier, gasProviderAddress, claimPayload)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to pack claim for GasTank: %w", err)
	}

	claimTx, err := sendAndWaitForTransaction(client901, big.NewInt(901), relayerPrivateKey, &gasTank901Address, big.NewInt(0), claimCalldata, *claimAccessList)
	if err != nil {
		return nil, nil, fmt.Errorf("claim transaction failed: %w", err)
	}
	logfIf(verbose, "Claim transaction successful: %s\n", claimTx.TxHash.Hex())

	// Capture claim cost details for final analysis
	claimBlock, err := client901.HeaderByNumber(context.Background(), claimTx.BlockNumber)
	if err != nil {
		log.Printf("Warning: could not get claim block header for final analysis: %v", err)
	}
	actualClaimCost := new(big.Int).Mul(new(big.Int).SetUint64(claimTx.GasUsed), claimTx.EffectiveGasPrice)

	// Find and decode the total reimbursement from the Claimed event
	claimedTopic := claimedEventABI.Events["Claimed"].ID

	var claimedLog *types.Log
	for _, logEntry := range claimTx.Logs {
		if logEntry.Address == gasTank901Address && len(logEntry.Topics) > 0 && logEntry.Topics[0] == claimedTopic {
			claimedLog = logEntry
			break
		}
	}

	if claimedLog != nil {
		unpackedData, err := claimedEventABI.Events["Claimed"].Inputs.Unpack(claimedLog.Data)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to unpack Claimed event data: %w", err)
		}
		eventClaimCost := unpackedData[2].(*big.Int)

		logIf(verbose, "\n--- Relayer Profit/Loss Analysis ---")

		// --- Relay TX Details ---
		logIf(verbose, "\n[Relay Transaction on Chain 902]")
		logfIf(verbose, "  - Gas Used:             %d units\n", relayTx.GasUsed)
		logfIf(verbose, "  - Calculated Gas:       %s units\n", new(big.Int).Div(eventRelayCost, relayBlock.BaseFee).String())
		relayGasDelta := new(big.Int).Sub(new(big.Int).Div(eventRelayCost, relayBlock.BaseFee), new(big.Int).SetUint64(relayTx.GasUsed))
		logfIf(verbose, "  - Relay Gas Delta:        %s units\n", relayGasDelta.String())
		logfIf(verbose, "\n  - Block Base Fee:       %s wei\n", relayBlock.BaseFee.String())
		logfIf(verbose, "  - Actual Cost:          %s wei\n", actualRelayCost.String())
		logfIf(verbose, "  - Cost declared in event:  %s wei\n", eventRelayCost.String())

		profit := new(big.Int).Sub(eventRelayCost, actualRelayCost)

		if verbose {
			if profit.Sign() < 0 {
				// Using a red color for the warning
				logfIf(verbose, "\033[31m>>>>> WARNING: RELAYER INCURRED A LOSS of %s wei <<<<<\033[0m\n", new(big.Int).Abs(profit).String())
			} else {
				logfIf(verbose, "Relayer Profit:               %s wei\n", profit.String())
			}
		}

		// --- Claim TX Details ---
		logIf(verbose, "\n[Claim Transaction on Chain 901]")
		logfIf(verbose, "  - Gas Used:             %d units\n", claimTx.GasUsed)
		logfIf(verbose, "  - Calculated Gas:       %s units\n", new(big.Int).Div(eventClaimCost, claimBlock.BaseFee).String())
		claimGasDelta := new(big.Int).Sub(new(big.Int).Div(eventClaimCost, claimBlock.BaseFee), new(big.Int).SetUint64(claimTx.GasUsed))
		logfIf(verbose, "  - Claim Gas Delta:       %s units\n", claimGasDelta.String())
		logfIf(verbose, "\n  - Block Base Fee:       %s wei\n", claimBlock.BaseFee.String())
		logfIf(verbose, "  - Actual Cost:          %s wei\n", actualClaimCost.String())
		logfIf(verbose, "  - Cost declared in event:      %s wei\n", eventClaimCost.String())

		profit = new(big.Int).Sub(eventClaimCost, actualClaimCost)

		if verbose {
			if profit.Sign() < 0 {
				// Using a red color for the warning
				logfIf(verbose, "\033[31m>>>>> WARNING: CLAIMER INCURRED A LOSS of %s wei <<<<<\033[0m\n", new(big.Int).Abs(profit).String())
			} else {
				logfIf(verbose, "Claimer Profit:               %s wei\n", profit.String())
			}
		}

		// Compare Gas Provider Balance before and after the claim
		logfIf(verbose, "Gas Provider Expected Balance: %s\n", (new(big.Int).Sub(maxDeposit, new(big.Int).Add(eventClaimCost, eventRelayCost))).String())
		gasProviderBalance, err := getCurrentGasProviderBalance(client901, gasProviderAddress, gasTank901Address)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to get current balance: %w", err)
		}
		logfIf(verbose, "Gas Provider Actual Balance: %s\n", gasProviderBalance.String())
		return relayGasDelta, claimGasDelta, nil

	} else {
		return nil, nil, fmt.Errorf("could not find Claimed event to log final analysis")
	}
}

func getCurrentGasProviderBalance(client *ethclient.Client, address common.Address, gasTankAddress common.Address) (*big.Int, error) {
	// Get current balance
	balanceOfCalldata, err := gasTankABI.Pack("balanceOf", address)
	if err != nil {
		return nil, fmt.Errorf("failed to pack balanceOf ABI: %w", err)
	}
	balanceBytes, err := client.CallContract(context.Background(), ethereum.CallMsg{To: &gasTankAddress, Data: balanceOfCalldata}, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to call balanceOf: %w", err)
	}
	currentBalance := new(big.Int).SetBytes(balanceBytes)
	return currentBalance, nil
}
