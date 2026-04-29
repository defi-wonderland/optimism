package server

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/ethereum-optimism/optimism/op-playground/explorer"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	"github.com/ethereum/go-ethereum/common"
)

type explorerHandler struct {
	readers map[string]*explorer.Reader
	names   []string
}

func newExplorerHandler(sys system.System) *explorerHandler {
	h := &explorerHandler{readers: make(map[string]*explorer.Reader)}

	// L1 reader, with L1 contracts from any L2 (they live on the same L1).
	l1Registry := explorer.NewRegistry()
	for _, c := range sys.Chains() {
		registerL1Contracts(l1Registry, c.L1Contracts)
	}
	l1RPC := sys.L1EL().Escape().UserRPC()
	h.readers["L1"] = explorer.New(l1RPC, l1Registry)
	h.names = append(h.names, "L1")

	// One reader per L2 (no decoding registry yet).
	for _, c := range sys.Chains() {
		if c.Kind != system.ChainKindL2 {
			continue
		}
		l2RPC := c.EL.Escape().UserRPC()
		h.readers[c.Name] = explorer.New(l2RPC, explorer.NewRegistry())
		h.names = append(h.names, c.Name)
	}
	return h
}

func registerL1Contracts(reg *explorer.Registry, c system.L1Contracts) {
	zero := common.Address{}
	if c.DisputeGameFactory != zero {
		_ = reg.Register("DisputeGameFactory", c.DisputeGameFactory, explorer.AbiSet["DisputeGameFactory"])
	}
	if c.OptimismPortal != zero {
		_ = reg.Register("OptimismPortal", c.OptimismPortal, explorer.AbiSet["OptimismPortal"])
	}
	if c.SystemConfig != zero {
		_ = reg.Register("SystemConfig", c.SystemConfig, explorer.AbiSet["SystemConfig"])
	}
	// AnchorStateRegistry isn't in L1Contracts directly; it's discovered at
	// runtime from the portal. We don't register it in the explorer registry
	// for now — the dispute panel's view of it suffices.
}

func (h *explorerHandler) chains(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(h.names)
}

func (h *explorerHandler) blocks(w http.ResponseWriter, r *http.Request) {
	chain := r.PathValue("chain")
	rd, ok := h.readers[chain]
	if !ok {
		http.NotFound(w, r)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	blocks, err := rd.RecentBlocks(ctx, 20)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(blocks)
}

func (h *explorerHandler) block(w http.ResponseWriter, r *http.Request) {
	chain := r.PathValue("chain")
	rd, ok := h.readers[chain]
	if !ok {
		http.NotFound(w, r)
		return
	}
	ref := r.PathValue("ref")
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	d, err := rd.Block(ctx, ref)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(d)
}

func (h *explorerHandler) tx(w http.ResponseWriter, r *http.Request) {
	chain := r.PathValue("chain")
	rd, ok := h.readers[chain]
	if !ok {
		http.NotFound(w, r)
		return
	}
	hash := r.PathValue("hash")
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	d, err := rd.Tx(ctx, hash)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(d)
}

func (h *explorerHandler) address(w http.ResponseWriter, r *http.Request) {
	chain := r.PathValue("chain")
	rd, ok := h.readers[chain]
	if !ok {
		http.NotFound(w, r)
		return
	}
	addr := r.PathValue("addr")
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	d, err := rd.Address(ctx, addr, 50)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(d)
}

func (h *explorerHandler) trace(w http.ResponseWriter, r *http.Request) {
	chain := r.PathValue("chain")
	rd, ok := h.readers[chain]
	if !ok {
		http.NotFound(w, r)
		return
	}
	hash := r.PathValue("hash")
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	t, err := rd.Trace(ctx, hash)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(t)
}
