package harness

import (
	"context"
	"errors"
	"fmt"
	"os"
	"runtime/debug"
	"slices"
	"sync"
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/devtest"
	oplog "github.com/ethereum-optimism/optimism/op-service/log"
	"github.com/ethereum-optimism/optimism/op-service/log/logfilter"
	"github.com/ethereum-optimism/optimism/op-service/testreq"
	"github.com/ethereum/go-ethereum/log"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
	"io"
)

type TestingFailure struct {
	Err error
}

func (f TestingFailure) Error() string {
	return f.Err.Error()
}

func AsError(v any) error {
	if err, ok := v.(error); ok {
		return err
	}
	return nil
}

func RecoverFailure(recovered any) error {
	if recovered == nil {
		return nil
	}
	var failure TestingFailure
	if errors.As(AsError(recovered), &failure) {
		return failure.Err
	}
	panic(recovered)
}

type TestingT struct {
	state  *testingState
	ctx    context.Context
	logger log.Logger
	tracer trace.Tracer
	req    *testreq.Assertions
	gate   *testreq.Assertions
}

type testingState struct {
	mu       sync.Mutex
	tempRoot string
	cleanups []func()
}

func NewLogger(ctx context.Context, w io.Writer) log.Logger {
	logHandler := oplog.NewLogHandler(w, oplog.DefaultCLIConfig())
	logHandler = logfilter.WrapFilterHandler(logHandler)
	logHandler.(logfilter.FilterHandler).Set(logfilter.DefaultMute())
	logHandler = logfilter.WrapContextHandler(logHandler)
	logger := log.NewLogger(logHandler)
	oplog.SetGlobalLogHandler(logHandler)
	logger.SetContext(ctx)
	return logger
}

func NewTestingT(ctx context.Context, w io.Writer, tempRoot string) *TestingT {
	logger := NewLogger(ctx, w)
	t := &TestingT{
		state: &testingState{
			tempRoot: tempRoot,
			cleanups: make([]func(), 0),
		},
		ctx:    ctx,
		logger: logger,
		tracer: otel.Tracer("op-playground"),
	}
	t.req = testreq.New(t)
	t.gate = testreq.New(t)
	return t
}

func (t *TestingT) failf(format string, args ...any) {
	err := fmt.Errorf(format, args...)
	t.logger.Error("op-playground runtime failure", "err", err)
	debug.PrintStack()
	panic(TestingFailure{Err: err})
}

var _ devtest.T = (*TestingT)(nil)
var _ testreq.TestingT = (*TestingT)(nil)

func (t *TestingT) DoCleanup() {
	t.state.mu.Lock()
	cleanups := append([]func(){}, t.state.cleanups...)
	t.state.cleanups = nil
	t.state.mu.Unlock()
	for _, cleanup := range slices.Backward(cleanups) {
		cleanup()
	}
}

func (t *TestingT) Cleanup(fn func()) {
	t.state.mu.Lock()
	defer t.state.mu.Unlock()
	t.state.cleanups = append(t.state.cleanups, fn)
}

func (t *TestingT) Ctx() context.Context {
	return t.ctx
}

func (t *TestingT) Deadline() (deadline time.Time, ok bool) {
	return time.Time{}, false
}

func (t *TestingT) Error(args ...any) {
	t.failf("%s", fmt.Sprint(args...))
}

func (t *TestingT) Errorf(format string, args ...any) {
	t.failf(format, args...)
}

func (t *TestingT) Fail() {
	t.failf("test failed")
}

func (t *TestingT) FailNow() {
	t.failf("test failed immediately")
}

func (t *TestingT) Gate() *testreq.Assertions {
	return t.gate
}

func (t *TestingT) MarkFlaky(string) {}
func (t *TestingT) Helper()          {}

func (t *TestingT) Log(args ...any) {
	t.logger.Info(fmt.Sprint(args...))
}

func (t *TestingT) Logf(format string, args ...any) {
	t.logger.Info(fmt.Sprintf(format, args...))
}

func (t *TestingT) Logger() log.Logger {
	return t.logger
}

func (t *TestingT) Name() string {
	return "playground"
}

func (t *TestingT) Parallel() {}

func (t *TestingT) Require() *testreq.Assertions {
	return t.req
}

func (t *TestingT) Run(name string, fn func(devtest.T)) {
	subCtx := devtest.AddTestScope(t.ctx, name)
	fn(t.WithCtx(subCtx))
}

func (t *TestingT) Skip(args ...any) {
	t.failf("unexpected skip: %s", fmt.Sprint(args...))
}

func (t *TestingT) SkipNow() {
	t.failf("unexpected skip")
}

func (t *TestingT) Skipf(format string, args ...any) {
	t.failf("unexpected skip: "+format, args...)
}

func (t *TestingT) Skipped() bool {
	return false
}

func (t *TestingT) TempDir() string {
	dir, err := os.MkdirTemp(t.state.tempRoot, "op-playground-*")
	if err != nil {
		t.failf("failed to create temp dir: %v", err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(dir); err != nil {
			t.logger.Error("failed to clean up temp dir", "dir", dir, "err", err)
		}
	})
	return dir
}

func (t *TestingT) Tracer() trace.Tracer {
	return t.tracer
}

func (t *TestingT) WithCtx(ctx context.Context) devtest.T {
	logger := t.logger.New()
	logger.SetContext(ctx)
	out := &TestingT{
		state:  t.state,
		ctx:    ctx,
		logger: logger,
		tracer: t.tracer,
	}
	out.req = testreq.New(out)
	out.gate = testreq.New(out)
	return out
}

func (t *TestingT) TestOnly() {}
