package server

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ethereum-optimism/optimism/op-playground/state"
)

type scriptInfo struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Desc string `json:"description"`
}

type scriptRunner struct {
	ctx        context.Context
	bus        *state.Bus
	scriptsDir string
	envVars    []string
	scripts    []scriptInfo

	runCounter atomic.Int64
	mu         sync.RWMutex
	runs       map[int64]*scriptRun
}

type scriptRun struct {
	ID     int64
	Name   string
	Done   chan struct{}
	Output []string
	mu     sync.Mutex
}

func newScriptRunner(ctx context.Context, bus *state.Bus, scriptsDir string, envVars []string) *scriptRunner {
	sr := &scriptRunner{
		ctx:        ctx,
		bus:        bus,
		scriptsDir: scriptsDir,
		envVars:    envVars,
		runs:       make(map[int64]*scriptRun),
	}
	sr.discover()
	return sr
}

func (sr *scriptRunner) discover() {
	castDir := filepath.Join(sr.scriptsDir, "cast")
	entries, err := os.ReadDir(castDir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sh") {
			continue
		}
		path := filepath.Join(castDir, e.Name())
		desc := readScriptDesc(path)
		name := strings.TrimSuffix(e.Name(), ".sh")
		sr.scripts = append(sr.scripts, scriptInfo{Name: name, Path: path, Desc: desc})
	}
}

func readScriptDesc(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "# ") && !strings.HasPrefix(line, "#!/") {
			return strings.TrimPrefix(line, "# ")
		}
	}
	return ""
}

func (sr *scriptRunner) listScripts(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sr.scripts)
}

func (sr *scriptRunner) runScript(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	var script *scriptInfo
	for i := range sr.scripts {
		if sr.scripts[i].Name == name {
			script = &sr.scripts[i]
			break
		}
	}
	if script == nil {
		http.Error(w, "script not found", http.StatusNotFound)
		return
	}

	id := sr.runCounter.Add(1)
	run := &scriptRun{ID: id, Name: name, Done: make(chan struct{})}
	sr.mu.Lock()
	sr.runs[id] = run
	sr.mu.Unlock()

	args := []string{script.Path}
	if argString := r.URL.Query().Get("args"); argString != "" {
		args = append(args, strings.Fields(argString)...)
	}
	cmd := exec.CommandContext(sr.ctx, "bash", args...)
	cmd.Env = append(os.Environ(), sr.envVars...)

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	sr.bus.Publish(state.NewEvent("script.start", map[string]any{"id": id, "name": name}))

	go func() {
		defer close(run.Done)
		if err := cmd.Start(); err != nil {
			run.addLine("ERROR: " + err.Error())
			return
		}

		go func() {
			scanner := bufio.NewScanner(stdout)
			for scanner.Scan() {
				run.addLine(scanner.Text())
			}
		}()
		go func() {
			scanner := bufio.NewScanner(stderr)
			for scanner.Scan() {
				run.addLine("[stderr] " + scanner.Text())
			}
		}()

		err := cmd.Wait()
		if err != nil {
			run.addLine("EXIT: " + err.Error())
			sr.bus.Publish(state.NewEvent("script.error", map[string]any{"id": id, "name": name, "error": err.Error()}))
		} else {
			sr.bus.Publish(state.NewEvent("script.done", map[string]any{"id": id, "name": name}))
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"run_id": id, "name": name})
}

func (sr *scriptRunner) streamRun(w http.ResponseWriter, r *http.Request) {
	var id int64
	fmt.Sscanf(r.PathValue("id"), "%d", &id)

	sr.mu.RLock()
	run, ok := sr.runs[id]
	sr.mu.RUnlock()
	if !ok {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	sent := 0
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		run.mu.Lock()
		lines := make([]string, len(run.Output[sent:]))
		copy(lines, run.Output[sent:])
		run.mu.Unlock()
		for _, line := range lines {
			fmt.Fprintf(w, "data: %s\n\n", line)
			sent++
		}
		if len(lines) > 0 {
			flusher.Flush()
		}

		select {
		case <-r.Context().Done():
			return
		case <-run.Done:
			run.mu.Lock()
			remaining := make([]string, len(run.Output[sent:]))
			copy(remaining, run.Output[sent:])
			run.mu.Unlock()
			for _, line := range remaining {
				fmt.Fprintf(w, "data: %s\n\n", line)
			}
			fmt.Fprintf(w, "event: done\ndata: finished\n\n")
			flusher.Flush()
			return
		case <-ticker.C:
		}
	}
}

func (run *scriptRun) addLine(line string) {
	run.mu.Lock()
	run.Output = append(run.Output, line)
	run.mu.Unlock()
}
