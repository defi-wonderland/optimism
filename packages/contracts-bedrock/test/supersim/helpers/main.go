package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"strconv"

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

type BuildIdentifierResult struct {
	Identifier  Identifier `json:"identifier"`
	Payload     string     `json:"payload"`
	MessageHash string     `json:"messageHash"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run . <script_name>")
		fmt.Println("Available scripts: build_id, get_access_list")
		os.Exit(1)
	}

	script := os.Args[1]
	switch script {
	case "build_id":
		getMessageIdentifier()
	case "get_access_list":
		// getAccessList()
	case "relay_message":
		// relayMessage()
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
