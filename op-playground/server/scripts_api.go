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

// scriptInfo is the listing-row representation. Description is the human
// summary either pulled from the sidecar JSON or, failing that, the second
// comment line of the script.
type scriptInfo struct {
	Name        string `json:"name"`
	Path        string `json:"path"`
	Title       string `json:"title,omitempty"`
	Desc        string `json:"description"`
	Family      string `json:"family,omitempty"`
}

// toolMeta is the optional sidecar (`<name>.json`) sitting next to a script.
// All fields are optional — anything missing is just elided in the UI.
type toolMeta struct {
	Title         string         `json:"title,omitempty"`
	Summary       string         `json:"summary,omitempty"`
	Family        string         `json:"family,omitempty"`
	Audience      string         `json:"audience,omitempty"`
	Description   string         `json:"description,omitempty"` // markdown-flavoured
	Prerequisites []toolMetaItem `json:"prerequisites,omitempty"`
	Calls         []toolMetaCall `json:"calls,omitempty"`
	Produces      []toolMetaItem `json:"produces,omitempty"`
	Inputs        []toolMetaItem `json:"inputs,omitempty"`
	UsageExample  string         `json:"usage_example,omitempty"`
	// Snapshots identifies state to capture before/after the tool runs so the
	// UI can render a diff. Currently supported: "dispute" — captures the
	// dispute system snapshot (gameImpls, initBonds, respectedGameType, …)
	// for the L2 chain.
	Snapshots []string `json:"snapshots,omitempty"`
}

type toolMetaItem struct {
	Title  string `json:"title,omitempty"`
	Detail string `json:"detail,omitempty"`
}

type toolMetaCall struct {
	Actor  string `json:"actor,omitempty"`
	Target string `json:"target,omitempty"`
	Method string `json:"method,omitempty"`
	Note   string `json:"note,omitempty"`
}

type scriptDetail struct {
	Name        string    `json:"name"`
	Title       string    `json:"title,omitempty"`
	Description string    `json:"description"`
	Family      string    `json:"family,omitempty"`
	Source      string    `json:"source"`
	Meta        *toolMeta `json:"meta,omitempty"`
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
		name := strings.TrimSuffix(e.Name(), ".sh")
		info := scriptInfo{Name: name, Path: path, Desc: readScriptDesc(path)}
		// Merge optional sidecar metadata (<name>.json next to <name>.sh).
		if meta := readToolMeta(filepath.Join(castDir, name+".json")); meta != nil {
			info.Title = meta.Title
			if meta.Summary != "" {
				info.Desc = meta.Summary
			}
			info.Family = meta.Family
		}
		sr.scripts = append(sr.scripts, info)
	}
}

func readToolMeta(path string) *toolMeta {
	body, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var m toolMeta
	if err := json.Unmarshal(body, &m); err != nil {
		return nil
	}
	return &m
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

func (sr *scriptRunner) getScript(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	for _, s := range sr.scripts {
		if s.Name != name {
			continue
		}
		body, err := os.ReadFile(s.Path)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		dir := filepath.Dir(s.Path)
		meta := readToolMeta(filepath.Join(dir, s.Name+".json"))
		detail := scriptDetail{
			Name:        s.Name,
			Title:       s.Title,
			Description: s.Desc,
			Family:      s.Family,
			Source:      string(body),
			Meta:        meta,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(detail)
		return
	}
	http.NotFound(w, r)
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
