package stack

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-service/apis"
	"github.com/ethereum-optimism/optimism/op-service/eth"
)

type ELNode interface {
	Common
	ChainID() eth.ChainID
	EthClient() apis.EthClient
	TransactionTimeout() time.Duration
	// UserRPC returns the node's user-facing RPC endpoint URL (e.g. "ws://127.0.0.1:12345").
	// For in-process sysgo-backed nodes the scheme is "ws://" but the endpoint accepts both
	// HTTP and WebSocket on the same TCP port.
	UserRPC() string
}
