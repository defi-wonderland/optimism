package system

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/dsl"
	"github.com/ethereum-optimism/optimism/op-service/eth"
	"github.com/ethereum/go-ethereum/common"
)

type ChainKind string

const (
	ChainKindL1 ChainKind = "l1"
	ChainKindL2 ChainKind = "l2"
)

// L1Contracts holds the L1 governance + dispute contract addresses for an L2.
type L1Contracts struct {
	SystemConfig       common.Address
	DisputeGameFactory common.Address
	OptimismPortal     common.Address
	L1StandardBridge   common.Address
}

type Chain struct {
	Name    string
	Kind    ChainKind
	ChainID eth.ChainID

	EL      *dsl.L2ELNode
	CL      *dsl.L2CLNode
	Batcher *dsl.L2Batcher

	L1EL *dsl.L1ELNode

	// L1Contracts is populated for L2 chains.
	L1Contracts L1Contracts
}

type System interface {
	Mode() string
	L1EL() *dsl.L1ELNode
	L1CL() *dsl.L1CLNode
	Chains() []Chain
	Supernode() *dsl.Supernode
	Wallet() *dsl.HDWallet
	AdvanceTime(amount time.Duration)
}
