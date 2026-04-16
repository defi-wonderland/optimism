package server

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/ethereum-optimism/optimism/op-playground/state"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	"github.com/ethereum/go-ethereum/common"
)

type fundHandler struct {
	sys system.System
	bus *state.Bus
}

type fundRequest struct {
	Chain  string `json:"chain"`
	To     string `json:"to"`
	Amount string `json:"amount_eth"`
}

func (h *fundHandler) fund(w http.ResponseWriter, r *http.Request) {
	var req fundRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if !common.IsHexAddress(req.To) {
		http.Error(w, "invalid address", http.StatusBadRequest)
		return
	}

	var found *system.Chain
	for _, c := range h.sys.Chains() {
		if c.Name == req.Chain {
			found = &c
			break
		}
	}
	if found == nil {
		http.Error(w, fmt.Sprintf("chain %q not found", req.Chain), http.StatusNotFound)
		return
	}

	h.bus.Publish(state.NewEvent("control.fund", map[string]string{
		"chain": req.Chain,
		"to":    req.To,
	}))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "note": "funding via faucet not yet wired — use cast send with the test account private key"})
}
