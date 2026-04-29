package server

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"time"

	"github.com/ethereum-optimism/optimism/op-playground/state"
	"github.com/ethereum-optimism/optimism/op-playground/system"
)

//go:embed static
var staticFS embed.FS

type Config struct {
	UIAddr     string
	Proxies    []ProxyConfig
	ScriptsDir string
	EnvVars    []string
}

type ProxyConfig struct {
	ListenAddr string
	TargetURL  string
	Name       string
}

type Server struct {
	cfg     Config
	sys     system.System
	agg     *state.Aggregator
	bus     *state.Bus
	acct    state.FundedAccount
	servers []*http.Server
}

func New(cfg Config, sys system.System, agg *state.Aggregator, bus *state.Bus, acct state.FundedAccount) *Server {
	return &Server{cfg: cfg, sys: sys, agg: agg, bus: bus, acct: acct}
}

func (s *Server) Run(ctx context.Context) error {
	mux := http.NewServeMux()

	// API routes
	mux.HandleFunc("GET /api/state", stateHandler(s.agg))
	mux.HandleFunc("GET /api/events", sseHandler(s.bus))

	chains := make([]chainInfo, 0)
	for _, p := range s.cfg.Proxies {
		chains = append(chains, chainInfo{
			Name: p.Name,
			RPC:  "http://" + p.ListenAddr,
			WS:   "ws://" + p.ListenAddr,
		})
	}
	mux.HandleFunc("GET /api/chains", chainsHandler(chains))

	mux.HandleFunc("GET /api/dispute/{chain}", disputeHandler(s.sys))
	mux.HandleFunc("POST /api/dispute/{chain}/games/{addr}/resolve", resolveGameHandler(s.sys, s.acct))

	exp := newExplorerHandler(s.sys)
	mux.HandleFunc("GET /api/explorer/chains", exp.chains)
	mux.HandleFunc("GET /api/explorer/{chain}/blocks", exp.blocks)
	mux.HandleFunc("GET /api/explorer/{chain}/block/{ref}", exp.block)
	mux.HandleFunc("GET /api/explorer/{chain}/tx/{hash}", exp.tx)
	mux.HandleFunc("GET /api/explorer/{chain}/tx/{hash}/trace", exp.trace)
	mux.HandleFunc("GET /api/explorer/{chain}/address/{addr}", exp.address)

	ctrl := &controlHandler{sys: s.sys, agg: s.agg, bus: s.bus}
	mux.HandleFunc("POST /api/control/sequencer/{chain}/start", ctrl.sequencerStart)
	mux.HandleFunc("POST /api/control/sequencer/{chain}/stop", ctrl.sequencerStop)
	mux.HandleFunc("POST /api/control/batcher/{chain}/start", ctrl.batcherStart)
	mux.HandleFunc("POST /api/control/batcher/{chain}/stop", ctrl.batcherStop)
	mux.HandleFunc("POST /api/control/sequencer/{chain}/step", ctrl.sequencerStep)
	mux.HandleFunc("POST /api/control/advance-time", ctrl.advanceTime)

	fh := &fundHandler{sys: s.sys, bus: s.bus}
	mux.HandleFunc("POST /api/control/fund", fh.fund)

	// Script runner
	if s.cfg.ScriptsDir != "" {
		sr := newScriptRunner(ctx, s.bus, s.cfg.ScriptsDir, s.cfg.EnvVars)
		mux.HandleFunc("GET /api/scripts", sr.listScripts)
		mux.HandleFunc("GET /api/scripts/{name}", sr.getScript)
		mux.HandleFunc("POST /api/scripts/{name}/run", sr.runScript)
		mux.HandleFunc("GET /api/scripts/runs/{id}/stream", sr.streamRun)
	}

	// Static files (embedded UI)
	staticContent, err := fs.Sub(staticFS, "static")
	if err != nil {
		return fmt.Errorf("embedded static fs: %w", err)
	}
	mux.Handle("/", http.FileServer(http.FS(staticContent)))

	// Start UI server
	uiServer := &http.Server{Addr: s.cfg.UIAddr, Handler: withCORS(mux)}
	s.servers = append(s.servers, uiServer)

	errCh := make(chan error, 1+len(s.cfg.Proxies))
	go func() {
		if err := uiServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- fmt.Errorf("UI server (%s): %w", s.cfg.UIAddr, err)
		}
	}()

	// Start reverse proxy servers
	for _, p := range s.cfg.Proxies {
		proxy := newReverseProxy(p.TargetURL)
		srv := &http.Server{Addr: p.ListenAddr, Handler: proxy}
		s.servers = append(s.servers, srv)
		go func(srv *http.Server, name string) {
			if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				errCh <- fmt.Errorf("proxy %s (%s): %w", name, srv.Addr, err)
			}
		}(srv, p.Name)
	}

	// Wait for context cancellation or fatal error
	select {
	case <-ctx.Done():
	case err := <-errCh:
		return err
	}

	// Graceful shutdown
	shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for _, srv := range s.servers {
		srv.Shutdown(shutCtx)
	}
	return nil
}

func (s *Server) WaitForReady(ctx context.Context) error {
	for _, srv := range append([]*http.Server{{Addr: s.cfg.UIAddr}}, s.servers...) {
		addr := srv.Addr
		for {
			conn, err := net.DialTimeout("tcp", addr, 100*time.Millisecond)
			if err == nil {
				conn.Close()
				break
			}
			select {
			case <-ctx.Done():
				return fmt.Errorf("timeout waiting for %s", addr)
			case <-time.After(50 * time.Millisecond):
			}
		}
	}
	return nil
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
