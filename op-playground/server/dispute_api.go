package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/ethereum-optimism/optimism/op-playground/dispute"
	"github.com/ethereum-optimism/optimism/op-playground/state"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	"github.com/ethereum/go-ethereum/common"
)

func resolveGameHandler(sys system.System, acct state.FundedAccount) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		chain := r.PathValue("chain")
		var found bool
		for _, c := range sys.Chains() {
			if c.Name == chain && c.Kind == system.ChainKindL2 {
				found = true
				break
			}
		}
		if !found {
			http.NotFound(w, r)
			return
		}

		addrHex := r.PathValue("addr")
		gameAddr := common.HexToAddress(addrHex)
		l1URL := sys.L1EL().Escape().UserRPC()

		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()

		// 1. Fast-forward L1 time past the deadline if needed.
		ff, err := dispute.FastForwardSeconds(ctx, l1URL, gameAddr)
		if err != nil {
			http.Error(w, fmt.Sprintf("read deadline: %v", err), http.StatusBadGateway)
			return
		}
		if ff > 0 {
			sys.AdvanceTime(time.Duration(ff) * time.Second)
		}

		// 2. resolveClaim + resolve.
		result, err := dispute.ResolveGame(ctx, l1URL, gameAddr, acct.PrivateKey)
		if err != nil {
			// Surface partial result if we got one (e.g. resolveClaim ok but
			// resolve reverted) so the UI can still link to the tx.
			if result != nil {
				result.AdvancedSeconds = ff
				result.Note = err.Error()
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadGateway)
				json.NewEncoder(w).Encode(result)
				return
			}
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		result.AdvancedSeconds = ff
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(result)
	}
}

func disputeHandler(sys system.System) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		want := r.PathValue("chain")

		var chain *system.Chain
		for i := range sys.Chains() {
			c := sys.Chains()[i]
			if c.Name == want {
				chain = &c
				break
			}
		}
		if chain == nil || chain.Kind != system.ChainKindL2 {
			http.NotFound(w, r)
			return
		}

		l1URL := sys.L1EL().Escape().UserRPC()

		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		snap, err := dispute.Read(ctx, l1URL, chain.Name,
			chain.L1Contracts.SystemConfig,
			chain.L1Contracts.DisputeGameFactory,
			chain.L1Contracts.OptimismPortal,
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(snap)
	}
}
