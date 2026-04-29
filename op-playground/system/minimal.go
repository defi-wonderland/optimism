package system

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/dsl"
	"github.com/ethereum-optimism/optimism/op-devstack/presets"
)

type minimalSystem struct {
	inner *presets.Minimal
}

func NewMinimalSystem(m *presets.Minimal) System {
	return &minimalSystem{inner: m}
}

func (s *minimalSystem) Mode() string { return "minimal" }

func (s *minimalSystem) L1EL() *dsl.L1ELNode { return s.inner.L1EL }
func (s *minimalSystem) L1CL() *dsl.L1CLNode { return s.inner.L1CL }

func (s *minimalSystem) Chains() []Chain {
	dep := s.inner.L2Chain.Escape().Deployment()
	return []Chain{
		{
			Name:    "L2",
			Kind:    ChainKindL2,
			ChainID: s.inner.L2EL.ChainID(),
			EL:      s.inner.L2EL,
			CL:      s.inner.L2CL,
			Batcher: s.inner.L2Batcher,
			L1Contracts: L1Contracts{
				SystemConfig:       dep.SystemConfigProxyAddr(),
				DisputeGameFactory: dep.DisputeGameFactoryProxyAddr(),
				OptimismPortal:     s.inner.L2Chain.DepositContractAddr(),
				L1StandardBridge:   dep.L1StandardBridgeProxyAddr(),
			},
		},
	}
}

func (s *minimalSystem) Supernode() *dsl.Supernode        { return nil }
func (s *minimalSystem) Wallet() *dsl.HDWallet            { return s.inner.Wallet }
func (s *minimalSystem) AdvanceTime(amount time.Duration) { s.inner.AdvanceTime(amount) }
