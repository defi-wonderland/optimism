package server

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/ethereum-optimism/optimism/op-playground/state"
)

func sseHandler(bus *state.Bus) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming not supported", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		ch, unsub := bus.Subscribe()
		defer unsub()

		for {
			select {
			case <-r.Context().Done():
				return
			case evt := <-ch:
				data, _ := json.Marshal(evt)
				fmt.Fprintf(w, "event: %s\ndata: %s\n\n", evt.Type, data)
				flusher.Flush()
			}
		}
	}
}
