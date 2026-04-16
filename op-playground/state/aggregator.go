package state

import (
	"context"
	"sync"
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/dsl"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	"github.com/ethereum-optimism/optimism/op-service/eth"
)

type Aggregator struct {
	sys  system.System
	bus  *Bus
	acct FundedAccount

	mu   sync.RWMutex
	snap Snapshot

	batcherState map[string]bool
}

func NewAggregator(sys system.System, bus *Bus, acct FundedAccount) *Aggregator {
	bs := make(map[string]bool)
	for _, c := range sys.Chains() {
		bs[c.Name] = true
	}
	return &Aggregator{
		sys:          sys,
		bus:          bus,
		acct:         acct,
		batcherState: bs,
	}
}

func (a *Aggregator) Snapshot() Snapshot {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.snap
}

func (a *Aggregator) SetBatcherRunning(chain string, running bool) {
	a.mu.Lock()
	a.batcherState[chain] = running
	a.mu.Unlock()
}

func (a *Aggregator) Run(ctx context.Context) {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.poll(ctx)
		}
	}
}

func (a *Aggregator) poll(ctx context.Context) {
	snap := Snapshot{
		Ts:   time.Now(),
		Mode: a.sys.Mode(),
		Acct: a.acct,
		L2s:  make(map[string]L2Status),
	}

	l1EL := a.sys.L1EL()
	if head, err := l1EL.EthClient().BlockRefByLabel(ctx, eth.Unsafe); err == nil {
		snap.L1.Head = head
	}
	if fin, err := l1EL.EthClient().BlockRefByLabel(ctx, eth.Finalized); err == nil {
		snap.L1.Finalized = fin
	}

	prevSnap := a.Snapshot()
	if snap.L1.Head.Number != prevSnap.L1.Head.Number {
		a.bus.Publish(NewEvent("l1.block", map[string]any{
			"number": snap.L1.Head.Number,
			"hash":   snap.L1.Head.Hash,
		}))
	}

	for _, chain := range a.sys.Chains() {
		status := a.pollL2(ctx, chain)
		snap.L2s[chain.Name] = status

		prev, hasPrev := prevSnap.L2s[chain.Name]
		if !hasPrev || status.Unsafe.Number != prev.Unsafe.Number {
			a.bus.Publish(NewEvent("l2.block", map[string]any{
				"chain":  chain.Name,
				"number": status.Unsafe.Number,
				"hash":   status.Unsafe.Hash,
			}))
		}
	}

	if sup := a.sys.Supernode(); sup != nil {
		snap.Sup = a.pollSupernode(ctx, sup)
	}

	a.mu.Lock()
	a.snap = snap
	a.mu.Unlock()
}

func (a *Aggregator) pollL2(ctx context.Context, chain system.Chain) L2Status {
	st := L2Status{ChainID: chain.ChainID}

	syncStatus := chain.CL.SyncStatus()
	if syncStatus != nil {
		st.Unsafe = syncStatus.UnsafeL2
		st.CrossUnsafe = syncStatus.CrossUnsafeL2
		st.LocalSafe = syncStatus.LocalSafeL2
		st.Safe = syncStatus.SafeL2
		st.Finalized = syncStatus.FinalizedL2
		st.CurrentL1 = syncStatus.CurrentL1
	}

	active, err := chain.CL.Escape().RollupAPI().SequencerActive(ctx)
	if err == nil {
		st.SeqActive = active
	}

	a.mu.RLock()
	st.BatcherRunning = a.batcherState[chain.Name]
	a.mu.RUnlock()

	return st
}

func (a *Aggregator) pollSupernode(ctx context.Context, sup *dsl.Supernode) *SupernodeStatus {
	status, err := sup.QueryAPI().SyncStatus(ctx)
	if err != nil {
		return nil
	}
	out := &SupernodeStatus{
		SafeTimestamp:      status.SafeTimestamp,
		LocalSafeTimestamp: status.LocalSafeTimestamp,
		Chains:             make(map[string]SuperChainInfo),
	}
	for chainID, cs := range status.Chains {
		out.Chains[chainID.String()] = SuperChainInfo{
			CrossUnsafe: cs.CrossUnsafeL2.Number,
			LocalSafe:   cs.LocalSafeL2.Number,
			Safe:        cs.SafeL2.Number,
		}
	}
	return out
}
