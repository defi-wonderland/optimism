package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"strconv"
	"strings"

	"github.com/ethereum/go-ethereum"
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

type BuildIdentifierResult struct {
	Identifier  Identifier `json:"identifier"`
	Payload     string     `json:"payload"`
	MessageHash string     `json:"messageHash"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run . <script_name>")
		fmt.Println("Available scripts: build_id, get_access_list, relay_message")
		os.Exit(1)
	}

	script := os.Args[1]
	switch script {
	case "build_id":
		getMessageIdentifier()
	case "get_access_list":
		getAccessList()
	case "relay_message":
		relayMessage()
	default:
		fmt.Printf("Unknown script: %s\n", script)
		os.Exit(1)
	}
}

// SentMessageData represents the data we're looking for in SentMessage events
type SentMessageData struct {
	Destination uint64         `json:"destination"`
	Target      common.Address `json:"target"`
	Sender      common.Address `json:"sender"`
	Message     []byte         `json:"message"`
}

// Builds message identifier from the SentMessage event
func getMessageIdentifier() {
	if len(os.Args) < 6 {
		log.Fatalf("Usage: go run . build_id <destination> <target> <sender> <message>")
	}

	// Parse command line arguments
	destination, err := strconv.ParseUint(os.Args[2], 10, 64)
	if err != nil {
		log.Fatalf("Invalid destination: %v", err)
	}

	target := common.HexToAddress(os.Args[3])
	sender := common.HexToAddress(os.Args[4])
	message := common.FromHex(os.Args[5])

	sentMessageData := SentMessageData{
		Destination: destination,
		Target:      target,
		Sender:      sender,
		Message:     message,
	}

	// Connect to the source chain (901) to find the SentMessage log
	client, err := ethclient.Dial("http://127.0.0.1:9545")
	if err != nil {
		log.Fatalf("Failed to connect to source chain: %v", err)
	}

	// L2ToL2CrossDomainMessenger address
	messengerAddr := common.HexToAddress("0x4200000000000000000000000000000000000023")

	// SentMessage event topic - keccak256("SentMessage(uint256,address,uint256,address,bytes)")
	sentMessageTopic := common.HexToHash("0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320")

	// Get the latest block
	latestBlock, err := client.BlockByNumber(context.Background(), nil)
	if err != nil {
		log.Fatalf("Failed to get latest block: %v", err)
	}

	// Search for SentMessage logs in recent blocks (last 100 blocks)
	var sentMessageLog *types.Log
	var foundBlock *types.Block
	found := false

	// Search through recent blocks
	for i := range uint64(100) {
		blockNumber := latestBlock.NumberU64() - i
		block, err := client.BlockByNumber(context.Background(), big.NewInt(int64(blockNumber)))
		if err != nil {
			continue
		}

		// Get receipts for all transactions in this block
		for _, tx := range block.Transactions() {
			receipt, err := client.TransactionReceipt(context.Background(), tx.Hash())
			if err != nil {
				continue
			}

			// Check each log in the receipt
			for _, logEntry := range receipt.Logs {
				if logEntry.Address == messengerAddr && len(logEntry.Topics) > 0 && logEntry.Topics[0] == sentMessageTopic {
					// Parse the SentMessage event data
					if len(logEntry.Topics) >= 4 && len(logEntry.Data) >= 64 {
						// Extract indexed parameters from topics
						eventDestination := new(big.Int).SetBytes(logEntry.Topics[1].Bytes())
						eventTarget := common.BytesToAddress(logEntry.Topics[2].Bytes())

						// Extract non-indexed parameters from data
						if len(logEntry.Data) >= 64 {
							eventSender := common.BytesToAddress(logEntry.Data[:32])

							// Extract message from data
							if len(logEntry.Data) >= 64 {
								messageOffset := new(big.Int).SetBytes(logEntry.Data[32:64]).Uint64()
								if uint64(len(logEntry.Data)) > messageOffset+32 {
									messageLength := new(big.Int).SetBytes(logEntry.Data[messageOffset : messageOffset+32]).Uint64()
									if uint64(len(logEntry.Data)) >= messageOffset+32+messageLength {
										eventMessage := logEntry.Data[messageOffset+32 : messageOffset+32+messageLength]

										// Check if this event matches our search criteria
										if eventDestination.Uint64() == sentMessageData.Destination &&
											eventTarget == sentMessageData.Target &&
											eventSender == sentMessageData.Sender &&
											common.Bytes2Hex(eventMessage) == common.Bytes2Hex(sentMessageData.Message) {

											sentMessageLog = logEntry
											foundBlock = block
											found = true
											break
										}
									}
								}
							}
						}
					}
				}
			}
			if found {
				break
			}
		}
		if found {
			break
		}
	}

	if !found {
		log.Fatalf("Could not find matching SentMessage event in recent blocks")
	}

	// Extract messageNonce from the event
	var messageNonce *big.Int
	if len(sentMessageLog.Topics) >= 4 {
		messageNonce = new(big.Int).SetBytes(sentMessageLog.Topics[3].Bytes())
	} else {
		log.Fatalf("Invalid SentMessage event: missing messageNonce")
	}

	// Compute message hash: keccak256(abi.encode(destination, target, messageNonce, sender, message))
	messageHashData := []byte{}
	messageHashData = append(messageHashData, common.LeftPadBytes(big.NewInt(int64(sentMessageData.Destination)).Bytes(), 32)...)
	messageHashData = append(messageHashData, common.LeftPadBytes(sentMessageData.Target.Bytes(), 32)...)
	messageHashData = append(messageHashData, common.LeftPadBytes(messageNonce.Bytes(), 32)...)
	messageHashData = append(messageHashData, common.LeftPadBytes(sentMessageData.Sender.Bytes(), 32)...)

	// For dynamic bytes, encode the offset and length
	messageOffset := big.NewInt(160) // 5 * 32 bytes for the fixed parameters
	messageHashData = append(messageHashData, common.LeftPadBytes(messageOffset.Bytes(), 32)...)
	messageHashData = append(messageHashData, common.LeftPadBytes(big.NewInt(int64(len(sentMessageData.Message))).Bytes(), 32)...)
	messageHashData = append(messageHashData, sentMessageData.Message...)

	// Pad the message to 32-byte boundary
	if len(sentMessageData.Message)%32 != 0 {
		padding := make([]byte, 32-len(sentMessageData.Message)%32)
		messageHashData = append(messageHashData, padding...)
	}

	messageHash := common.BytesToHash(crypto.Keccak256(messageHashData))

	// Build identifier according to SuperSim guide
	identifier := Identifier{
		Origin:      sentMessageLog.Address,
		BlockNumber: big.NewInt(int64(sentMessageLog.BlockNumber)),
		LogIndex:    big.NewInt(int64(sentMessageLog.Index)),
		Timestamp:   big.NewInt(int64(foundBlock.Time())),
		ChainID:     big.NewInt(901), // Source chain ID
	}

	// Build payload: concatenate all topics and data in order
	var payload []byte

	// Add all topics in order
	for _, topic := range sentMessageLog.Topics {
		payload = append(payload, topic.Bytes()...)
	}

	// Add the event data
	if len(sentMessageLog.Data) > 0 {
		payload = append(payload, sentMessageLog.Data...)
	}

	result := BuildIdentifierResult{
		Identifier:  identifier,
		Payload:     "0x" + common.Bytes2Hex(payload),
		MessageHash: messageHash.Hex(),
	}

	jsonResult, err := json.Marshal(result)
	if err != nil {
		log.Fatalf("Failed to marshal result: %v", err)
	}

	fmt.Println(string(jsonResult))
}

// GetAccessListForIdentifierRequest mirrors the structure for the admin RPC call
type GetAccessListForIdentifierRequest struct {
	Identifier
	Payload string `json:"payload"`
}

// GetAccessListResponse mirrors the structure of the admin RPC response
type GetAccessListResponse struct {
	AccessList types.AccessList `json:"accessList"`
}

// AccessListItem represents a single access list item for output
type AccessListItem struct {
	Address           common.Address `json:"address"`
	StorageKeys       []common.Hash  `json:"storageKeys"`
	StorageKeysLength int            `json:"storageKeysLength"`
}

// AccessListResult represents the final output structure
type AccessListResult struct {
	Length     uint64           `json:"length"`
	AccessList []AccessListItem `json:"accessList"`
}

// Builds access list using the message identifier and payload
func getAccessList() {
	if len(os.Args) < 9 {
		log.Fatalf("Usage: %s <origin> <blockNumber> <logIndex> <timestamp> <chainId> <payload> <destination_chain_id>", os.Args[0])
	}

	// Parse command line arguments
	origin := os.Args[2]
	blockNumber := os.Args[3]
	logIndex := os.Args[4]
	timestamp := os.Args[5]
	chainId := os.Args[6]
	payload := os.Args[7]
	// destinationChainID := os.Args[8] // Not used in this implementation

	// Create identifier from command line arguments
	blockNum, _ := new(big.Int).SetString(blockNumber, 10)
	logIdx, _ := new(big.Int).SetString(logIndex, 10)
	ts, _ := new(big.Int).SetString(timestamp, 10)
	cid, _ := new(big.Int).SetString(chainId, 10)

	identifier := Identifier{
		Origin:      common.HexToAddress(origin),
		BlockNumber: blockNum,
		LogIndex:    logIdx,
		Timestamp:   ts,
		ChainID:     cid,
	}

	// Convert payload string to bytes
	payloadBytes := common.FromHex(payload)

	// Get access list using the shared function
	accessList, err := _getAccessList(identifier, payloadBytes)
	if err != nil {
		log.Fatalf("Failed to get access list: %v", err)
	}

	// Convert to our result format
	result := AccessListResult{
		Length:     uint64(len(*accessList)),
		AccessList: make([]AccessListItem, len(*accessList)),
	}

	for i, item := range *accessList {
		result.AccessList[i] = AccessListItem{
			Address:           item.Address,
			StorageKeys:       item.StorageKeys,
			StorageKeysLength: len(item.StorageKeys),
		}
	}

	jsonResult, err := json.Marshal(result)
	if err != nil {
		log.Fatalf("Failed to marshal result: %v", err)
	}

	fmt.Println(string(jsonResult))
}

func _getAccessList(id Identifier, payload []byte) (*types.AccessList, error) {
	// Connect to the SuperSim admin RPC
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

func sendAndWaitForTransaction(client *ethclient.Client, chainID *big.Int, pk *ecdsa.PrivateKey, to *common.Address, value *big.Int, data []byte, accessList types.AccessList) (*types.Receipt, error) {
	fromAddress := crypto.PubkeyToAddress(*pk.Public().(*ecdsa.PublicKey))
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to get nonce: %w", err)
	}

	latestBlock, err := client.BlockByNumber(context.Background(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get latest block: %w", err)
	}

	txData := &types.DynamicFeeTx{
		ChainID:    chainID,
		Nonce:      nonce,
		GasFeeCap:  new(big.Int).Mul(latestBlock.BaseFee(), big.NewInt(2)),
		GasTipCap:  big.NewInt(0),
		To:         to,
		Value:      value,
		Data:       data,
		Gas:        2000000,
		AccessList: accessList,
	}

	tx := types.NewTx(txData)
	signedTx, err := types.SignTx(tx, types.NewLondonSigner(chainID), pk)
	if err != nil {
		return nil, fmt.Errorf("failed to sign transaction: %w", err)
	}

	if err = client.SendTransaction(context.Background(), signedTx); err != nil {
		return nil, fmt.Errorf("failed to send transaction: %w", err)
	}

	receipt, err := bind.WaitMined(context.Background(), client, signedTx)
	if err != nil && receipt == nil {
		return nil, fmt.Errorf("failed to wait for transaction to be mined: %w", err)
	}

	if receipt.Status == 0 {
		callMsg := ethereum.CallMsg{
			From:  fromAddress,
			To:    to,
			Value: value,
			Data:  data,
		}
		_, callErr := client.CallContract(context.Background(), callMsg, receipt.BlockNumber)
		if callErr != nil {
			return nil, fmt.Errorf("transaction failed with status 0. Revert reason: %v", callErr)
		}
		return nil, fmt.Errorf("transaction failed with status 0 (revert reason not found)")
	}

	return receipt, nil
}

// getTransactionReceipt fetches the transaction receipt and extracts events
func getTransactionReceipt(client *ethclient.Client, txHash common.Hash, targetAddr common.Address) ([]EventData, error) {
	receipt, err := client.TransactionReceipt(context.Background(), txHash)
	if err != nil {
		return nil, fmt.Errorf("failed to get transaction receipt: %w", err)
	}

	var events []EventData
	for _, log := range receipt.Logs {
		// Only include events from the target address
		if log.Address == targetAddr {
			event := EventData{
				Address:  log.Address.Hex(),
				Topics:   make([]string, len(log.Topics)),
				Data:     "0x" + common.Bytes2Hex(log.Data),
				LogIndex: int(log.Index),
			}

			// Convert topics to hex strings
			for i, topic := range log.Topics {
				event.Topics[i] = topic.Hex()
			}

			events = append(events, event)
		}
	}

	return events, nil
}

// EventData represents an event emitted during the transaction
type EventData struct {
	Address  string   `json:"address"`
	Topics   []string `json:"topics"`
	Data     string   `json:"data"`
	LogIndex int      `json:"logIndex"`
}

// RelayResult represents the result of the relay operation
type RelayResult struct {
	Success    bool        `json:"success"`
	Result     string      `json:"result"` // hex-encoded bytes
	Events     []EventData `json:"events"`
	EventCount int         `json:"eventCount"`
	Error      string      `json:"error,omitempty"`
}

// Relay message using the identifier and payload
func relayMessage() {
	if len(os.Args) < 6 {
		log.Fatalf("Usage: %s relay_message <target> <destination_chain_id> <private_key> <relay_calldata> <access_list_json>", os.Args[0])
	}

	// Parse command line arguments
	target := os.Args[2]
	destinationChainID := os.Args[3]
	privateKeyHex := os.Args[4]
	relayCalldataHex := os.Args[5]
	accessListJSON := os.Args[6]

	// Parse relay calldata from hex
	relayCalldata := common.FromHex(relayCalldataHex)

	// Parse access list from JSON array format
	var accessListArray []struct {
		Address     string   `json:"address"`
		StorageKeys []string `json:"storageKeys"`
	}
	if err := json.Unmarshal([]byte(accessListJSON), &accessListArray); err != nil {
		log.Fatalf("Failed to parse access list JSON: %v", err)
	}

	// Convert access list to types.AccessList
	accessList := make(types.AccessList, len(accessListArray))
	for i, item := range accessListArray {
		accessList[i] = types.AccessTuple{
			Address:     common.HexToAddress(item.Address),
			StorageKeys: make([]common.Hash, len(item.StorageKeys)),
		}
		for j, key := range item.StorageKeys {
			accessList[i].StorageKeys[j] = common.HexToHash(key)
		}
	}

	// Load private key
	privateKeyHex = strings.TrimPrefix(privateKeyHex, "0x")
	privateKey, err := crypto.HexToECDSA(privateKeyHex)
	if err != nil {
		log.Fatalf("Failed to load private key: %v", err)
	}

	// Parse destination chain ID
	destChainID, _ := new(big.Int).SetString(destinationChainID, 10)

	// Connect to destination chain
	client, err := ethclient.Dial("http://127.0.0.1:9546")
	if err != nil {
		log.Fatalf("Failed to connect to destination chain: %v", err)
	}

	// Relay the message
	result := _relayMessage(client, destChainID, privateKey, target, relayCalldata, &accessList)

	// Output result as JSON
	jsonResult, err := json.Marshal(result)
	if err != nil {
		log.Fatalf("Failed to marshal result: %v", err)
	}

	fmt.Println(string(jsonResult))
}

func _relayMessage(client *ethclient.Client, chainID *big.Int, privateKey *ecdsa.PrivateKey, target string, relayCalldata []byte, accessList *types.AccessList) RelayResult {
	targetAddr := common.HexToAddress(target)

	// Send transaction
	receipt, err := sendAndWaitForTransaction(client, chainID, privateKey, &targetAddr, big.NewInt(0), relayCalldata, *accessList)
	if err != nil {
		return RelayResult{Success: false, Error: fmt.Sprintf("Relay transaction failed: %v", err)}
	}

	// Check if transaction was successful
	if receipt.Status == 0 {
		return RelayResult{Success: false, Error: "Transaction reverted"}
	}

	// Get events from the transaction receipt
	events, err := getTransactionReceipt(client, receipt.TxHash, targetAddr)
	if err != nil {
		// Log the error but don't fail the relay
		fmt.Printf("Warning: Failed to get transaction receipt: %v\n", err)
		events = []EventData{}
	}

	// Return the transaction hash as the result along with events
	return RelayResult{
		Success:    true,
		Result:     "0x" + common.Bytes2Hex(receipt.TxHash.Bytes()),
		Events:     events,
		EventCount: len(events),
	}
}
