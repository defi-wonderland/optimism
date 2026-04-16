package system

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/dsl"
	"github.com/ethereum-optimism/optimism/op-service/eth"
)

type ChainKind string

const (
	ChainKindL1 ChainKind = "l1"
	ChainKindL2 ChainKind = "l2"
)

type Chain struct {
	Name    string
	Kind    ChainKind
	ChainID eth.ChainID

	EL      *dsl.L2ELNode
	CL      *dsl.L2CLNode
	Batcher *dsl.L2Batcher

	L1EL *dsl.L1ELNode
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
