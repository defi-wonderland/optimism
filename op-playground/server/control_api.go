package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/ethereum-optimism/optimism/op-playground/state"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	"github.com/ethereum-optimism/optimism/op-service/eth"
)

type controlHandler struct {
	sys system.System
	agg *state.Aggregator
	bus *state.Bus
}

func (h *controlHandler) findChain(name string) *system.Chain {
	for _, c := range h.sys.Chains() {
		if c.Name == name {
			return &c
		}
	}
	return nil
}

func (h *controlHandler) sequencerStart(w http.ResponseWriter, r *http.Request) {
	chain := h.findChain(r.PathValue("chain"))
	if chain == nil {
		http.Error(w, "chain not found", http.StatusNotFound)
		return
	}
	err := safeCall(func() {
		chain.CL.StartSequencer()
	})
	if err != nil {
		writeError(w, err)
		return
	}
	h.bus.Publish(state.NewEvent("control.sequencer.start", map[string]string{"chain": chain.Name}))
	writeOK(w)
}

func (h *controlHandler) sequencerStop(w http.ResponseWriter, r *http.Request) {
	chain := h.findChain(r.PathValue("chain"))
	if chain == nil {
		http.Error(w, "chain not found", http.StatusNotFound)
		return
	}
	err := safeCall(func() {
		chain.CL.StopSequencer()
	})
	if err != nil {
		writeError(w, err)
		return
	}
	h.bus.Publish(state.NewEvent("control.sequencer.stop", map[string]string{"chain": chain.Name}))
	writeOK(w)
}

func (h *controlHandler) batcherStart(w http.ResponseWriter, r *http.Request) {
	chain := h.findChain(r.PathValue("chain"))
	if chain == nil {
		http.Error(w, "chain not found", http.StatusNotFound)
		return
	}
	err := safeCall(func() {
		chain.Batcher.Start()
	})
	if err != nil {
		writeError(w, err)
		return
	}
	h.agg.SetBatcherRunning(chain.Name, true)
	h.bus.Publish(state.NewEvent("control.batcher.start", map[string]string{"chain": chain.Name}))
	writeOK(w)
}

func (h *controlHandler) batcherStop(w http.ResponseWriter, r *http.Request) {
	chain := h.findChain(r.PathValue("chain"))
	if chain == nil {
		http.Error(w, "chain not found", http.StatusNotFound)
		return
	}
	err := safeCall(func() {
		chain.Batcher.Stop()
	})
	if err != nil {
		writeError(w, err)
		return
	}
	h.agg.SetBatcherRunning(chain.Name, false)
	h.bus.Publish(state.NewEvent("control.batcher.stop", map[string]string{"chain": chain.Name}))
	writeOK(w)
}

func (h *controlHandler) sequencerStep(w http.ResponseWriter, r *http.Request) {
	chain := h.findChain(r.PathValue("chain"))
	if chain == nil {
		http.Error(w, "chain not found", http.StatusNotFound)
		return
	}

	var result map[string]any
	err := safeCall(func() {
		before := chain.EL.BlockRefByLabel(eth.Unsafe)

		chain.CL.StartSequencer()
		defer chain.CL.StopSequencer()

		deadline := time.After(10 * time.Second)
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-deadline:
				return
			case <-ticker.C:
				cur := chain.EL.BlockRefByLabel(eth.Unsafe)
				if cur.Number > before.Number {
					result = map[string]any{
						"before": before.Number,
						"after":  cur.Number,
						"hash":   cur.Hash,
						"time":   cur.Time,
					}
					return
				}
			}
		}
	})
	if err != nil {
		writeError(w, err)
		return
	}
	h.bus.Publish(state.NewEvent("control.sequencer.step", map[string]any{"chain": chain.Name, "result": result}))
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"status": "ok", "step": result})
}

func (h *controlHandler) advanceTime(w http.ResponseWriter, r *http.Request) {
	secondsStr := r.URL.Query().Get("seconds")
	if secondsStr == "" {
		http.Error(w, "missing seconds query param", http.StatusBadRequest)
		return
	}
	var seconds int64
	if _, err := fmt.Sscanf(secondsStr, "%d", &seconds); err != nil || seconds <= 0 {
		http.Error(w, "invalid seconds value", http.StatusBadRequest)
		return
	}
	duration := time.Duration(seconds) * time.Second
	err := safeCall(func() { h.sys.AdvanceTime(duration) })
	if err != nil {
		writeError(w, err)
		return
	}
	h.bus.Publish(state.NewEvent("control.advance_time", map[string]any{"seconds": seconds}))
	writeOK(w)
}

func safeCall(fn func()) (err error) {
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(error); ok {
				err = e
			}
		}
	}()
	fn()
	return nil
}

func writeOK(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func writeError(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
