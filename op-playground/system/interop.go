package system

import (
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/dsl"
	"github.com/ethereum-optimism/optimism/op-devstack/presets"
)

type interopSystem struct {
	inner *presets.TwoL2SupernodeInterop
}

func NewInteropSystem(s *presets.TwoL2SupernodeInterop) System {
	return &interopSystem{inner: s}
}

func (s *interopSystem) Mode() string { return "interop" }

func (s *interopSystem) L1EL() *dsl.L1ELNode { return s.inner.L1EL }
func (s *interopSystem) L1CL() *dsl.L1CLNode { return s.inner.L1CL }

func (s *interopSystem) Chains() []Chain {
	depA := s.inner.L2A.Escape().Deployment()
	depB := s.inner.L2B.Escape().Deployment()
	return []Chain{
		{
			Name:    "L2A",
			Kind:    ChainKindL2,
			ChainID: s.inner.L2ELA.ChainID(),
			EL:      s.inner.L2ELA,
			CL:      s.inner.L2ACL,
			Batcher: s.inner.L2BatcherA,
			L1Contracts: L1Contracts{
				SystemConfig:       depA.SystemConfigProxyAddr(),
				DisputeGameFactory: depA.DisputeGameFactoryProxyAddr(),
				OptimismPortal:     s.inner.L2A.DepositContractAddr(),
				L1StandardBridge:   depA.L1StandardBridgeProxyAddr(),
			},
		},
		{
			Name:    "L2B",
			Kind:    ChainKindL2,
			ChainID: s.inner.L2ELB.ChainID(),
			EL:      s.inner.L2ELB,
			CL:      s.inner.L2BCL,
			Batcher: s.inner.L2BatcherB,
			L1Contracts: L1Contracts{
				SystemConfig:       depB.SystemConfigProxyAddr(),
				DisputeGameFactory: depB.DisputeGameFactoryProxyAddr(),
				OptimismPortal:     s.inner.L2B.DepositContractAddr(),
				L1StandardBridge:   depB.L1StandardBridgeProxyAddr(),
			},
		},
	}
}

func (s *interopSystem) Supernode() *dsl.Supernode        { return s.inner.Supernode }
func (s *interopSystem) Wallet() *dsl.HDWallet            { return s.inner.Wallet }
func (s *interopSystem) AdvanceTime(amount time.Duration) { s.inner.AdvanceTime(amount) }
