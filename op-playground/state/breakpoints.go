package state

import "sync"

type ComponentState string

const (
	Running ComponentState = "running"
	Paused  ComponentState = "paused"
)

type Breakpoints struct {
	mu    sync.RWMutex
	state map[string]map[string]ComponentState // component -> chain -> state
}

func NewBreakpoints(chains []string) *Breakpoints {
	b := &Breakpoints{
		state: make(map[string]map[string]ComponentState),
	}
	for _, component := range []string{"sequencer", "batcher"} {
		b.state[component] = make(map[string]ComponentState)
		for _, chain := range chains {
			b.state[component][chain] = Running
		}
	}
	return b
}

func (b *Breakpoints) Get(component, chain string) ComponentState {
	b.mu.RLock()
	defer b.mu.RUnlock()
	if m, ok := b.state[component]; ok {
		if s, ok := m[chain]; ok {
			return s
		}
	}
	return Running
}

func (b *Breakpoints) Set(component, chain string, s ComponentState) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if _, ok := b.state[component]; !ok {
		b.state[component] = make(map[string]ComponentState)
	}
	b.state[component][chain] = s
}

func (b *Breakpoints) All() map[string]map[string]ComponentState {
	b.mu.RLock()
	defer b.mu.RUnlock()
	out := make(map[string]map[string]ComponentState)
	for comp, chains := range b.state {
		m := make(map[string]ComponentState)
		for chain, s := range chains {
			m[chain] = s
		}
		out[comp] = m
	}
	return out
}
