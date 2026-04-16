package server

import (
	"encoding/json"
	"net/http"

	"github.com/ethereum-optimism/optimism/op-playground/state"
)

func stateHandler(agg *state.Aggregator) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		snap := agg.Snapshot()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(snap)
	}
}

type chainInfo struct {
	Name    string `json:"name"`
	ChainID string `json:"chain_id"`
	RPC     string `json:"rpc"`
	WS      string `json:"ws"`
}

func chainsHandler(chains []chainInfo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(chains)
	}
}
