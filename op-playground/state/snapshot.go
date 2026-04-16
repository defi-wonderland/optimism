package state

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-service/eth"
)

type Snapshot struct {
	Ts   time.Time            `json:"ts"`
	Mode string               `json:"mode"`
	L1   L1Status             `json:"l1"`
	L2s  map[string]L2Status  `json:"l2s"`
	Sup  *SupernodeStatus     `json:"supernode,omitempty"`
	Acct FundedAccount        `json:"account"`
}

type L1Status struct {
	Head      eth.L1BlockRef `json:"head"`
	Finalized eth.L1BlockRef `json:"finalized"`
}

type L2Status struct {
	ChainID         eth.ChainID    `json:"chain_id"`
	Unsafe          eth.L2BlockRef `json:"unsafe"`
	CrossUnsafe     eth.L2BlockRef `json:"cross_unsafe"`
	LocalSafe       eth.L2BlockRef `json:"local_safe"`
	Safe            eth.L2BlockRef `json:"safe"`
	Finalized       eth.L2BlockRef `json:"finalized"`
	CurrentL1       eth.L1BlockRef `json:"current_l1"`
	SeqActive       bool           `json:"sequencer_active"`
	BatcherRunning  bool           `json:"batcher_running"`
}

type SupernodeStatus struct {
	SafeTimestamp      uint64                    `json:"safe_timestamp"`
	LocalSafeTimestamp uint64                    `json:"local_safe_timestamp"`
	Chains             map[string]SuperChainInfo `json:"chains"`
}

type SuperChainInfo struct {
	CrossUnsafe uint64 `json:"cross_unsafe"`
	LocalSafe   uint64 `json:"local_safe"`
	Safe        uint64 `json:"safe"`
}

type FundedAccount struct {
	Address    string `json:"address"`
	PrivateKey string `json:"private_key"`
}
