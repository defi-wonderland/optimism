package main

import (
	"context"
	"fmt"
	"io"
	"math/big"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/ethereum-optimism/optimism/op-chain-ops/devkeys"
	"github.com/ethereum-optimism/optimism/op-devstack/devtest"
	"github.com/ethereum-optimism/optimism/op-devstack/presets"
	"github.com/ethereum-optimism/optimism/op-playground/harness"
	"github.com/ethereum-optimism/optimism/op-playground/server"
	"github.com/ethereum-optimism/optimism/op-playground/state"
	"github.com/ethereum-optimism/optimism/op-playground/system"
	opservice "github.com/ethereum-optimism/optimism/op-service"
	"github.com/ethereum-optimism/optimism/op-service/cliapp"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/urfave/cli/v2"
)

const asciiArt = `
  ____  ____        ____  _                                              _
 /  _ \/  __\      /  __\/ \   ____  _  _  ___  ____ ____  _   _ ____  _| |
 | / \||  \/|_____ |  \/|| |  /  _ \/ \/ \/ _ \/ ___/  _ \/ | | |  _ \/ _ |
 | \_/||  __/\____\|  __/| |__| / \|  \  / /_\/| |  | / \| | | | | \| / \ |
 \____/\_/         \_/   \____\_/\_/\_/\_\____/\_/  \_/\_/\____|_| \__\_/\_|`

var (
	Version     = "v0.0.0"
	VersionMeta = "dev"
	GitCommit   string
	GitDate     string

	envPrefix = "OP_PLAYGROUND"
	dirFlag   = &cli.PathFlag{
		Name:    "dir",
		Usage:   "data directory for playground state",
		EnvVars: opservice.PrefixEnvVar(envPrefix, "DIR"),
		Value: func() string {
			home, err := os.UserHomeDir()
			if err != nil {
				home, _ = os.Getwd()
			}
			return filepath.Join(home, ".op-playground")
		}(),
	}
	interopFlag = &cli.BoolFlag{
		Name:    "interop",
		Usage:   "start 2-chain interop mode with supernode",
		EnvVars: opservice.PrefixEnvVar(envPrefix, "INTEROP"),
	}
	uiPortFlag = &cli.IntFlag{
		Name:    "ui-port",
		Usage:   "port for the playground dashboard",
		EnvVars: opservice.PrefixEnvVar(envPrefix, "UI_PORT"),
		Value:   7777,
	}
	l1PortFlag = &cli.IntFlag{
		Name:    "l1-port",
		Usage:   "port for the L1 RPC proxy",
		EnvVars: opservice.PrefixEnvVar(envPrefix, "L1_PORT"),
		Value:   8547,
	}
	l2PortBaseFlag = &cli.IntFlag{
		Name:    "l2-port-base",
		Usage:   "starting port for L2 RPC proxies (each chain gets base+i)",
		EnvVars: opservice.PrefixEnvVar(envPrefix, "L2_PORT_BASE"),
		Value:   8545,
	}
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer cancel()
	if err := run(ctx, os.Args, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	app := cli.NewApp()
	app.Writer = stdout
	app.ErrWriter = stderr
	app.Version = opservice.FormatVersion(Version, GitCommit, GitDate, VersionMeta)
	app.Name = "op-playground"
	app.Usage = "interactive OP Stack dev environment with web UI and breakpoints"
	app.Flags = cliapp.ProtectFlags([]cli.Flag{dirFlag, interopFlag, uiPortFlag, l1PortFlag, l2PortBaseFlag})
	app.OnUsageError = func(cliCtx *cli.Context, err error, isSubcommand bool) error {
		if !cliCtx.App.HideHelp {
			_ = cli.ShowAppHelp(cliCtx)
		}
		return err
	}
	app.Action = func(cliCtx *cli.Context) error {
		return runPlayground(cliCtx.Context, cliCtx.App.ErrWriter,
			cliCtx.String(dirFlag.Name),
			cliCtx.Bool(interopFlag.Name),
			cliCtx.Int(uiPortFlag.Name),
			cliCtx.Int(l1PortFlag.Name),
			cliCtx.Int(l2PortBaseFlag.Name),
		)
	}
	return app.RunContext(ctx, args)
}

func runPlayground(ctx context.Context, stderr io.Writer, dataDir string, interop bool, uiPort, l1Port, l2PortBase int) error {
	fmt.Fprintf(stderr, "%s\n\n", asciiArt)

	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return fmt.Errorf("create data dir: %w", err)
	}
	tempRoot := filepath.Join(dataDir, "tmp")
	if err := os.MkdirAll(tempRoot, 0o755); err != nil {
		return fmt.Errorf("create temp dir: %w", err)
	}

	devtest.RootContext = ctx
	t := harness.NewTestingT(ctx, stderr, tempRoot)
	defer t.DoCleanup()

	acct, err := fundedAccount()
	if err != nil {
		return err
	}
	fmt.Fprintf(stderr, "Test Account Address:     %s\n", acct.Address)
	fmt.Fprintf(stderr, "Test Account Private Key: %s\n", acct.PrivateKey)

	var sys system.System
	if interop {
		inner, err := newInteropSystem(t)
		if err != nil {
			return err
		}
		sys = system.NewInteropSystem(inner)
	} else {
		inner, err := newMinimalSystem(t)
		if err != nil {
			return err
		}
		sys = system.NewMinimalSystem(inner)
	}

	bus := state.NewBus()
	agg := state.NewAggregator(sys, bus, acct)
	go agg.Run(ctx)

	cfg := buildServerConfig(sys, uiPort, l1Port, l2PortBase, acct)
	printEndpoints(stderr, cfg)

	srv := server.New(cfg, sys, agg, bus, acct)
	return srv.Run(ctx)
}

func buildServerConfig(sys system.System, uiPort, l1Port, l2PortBase int, acct state.FundedAccount) server.Config {
	cfg := server.Config{
		UIAddr: fmt.Sprintf("localhost:%d", uiPort),
	}

	chains := sys.Chains()

	// L1 proxy
	l1RPC := sys.L1EL().Escape().UserRPC()
	cfg.Proxies = append(cfg.Proxies, server.ProxyConfig{
		ListenAddr: fmt.Sprintf("localhost:%d", l1Port),
		TargetURL:  l1RPC,
		Name:       "L1",
	})

	// L2 proxies
	for i, chain := range chains {
		port := l2PortBase + i
		cfg.Proxies = append(cfg.Proxies, server.ProxyConfig{
			ListenAddr: fmt.Sprintf("localhost:%d", port),
			TargetURL:  chain.EL.Escape().UserRPC(),
			Name:       chain.Name,
		})
	}

	// Scripts
	exePath, _ := os.Executable()
	scriptsDir := filepath.Join(filepath.Dir(exePath), "..", "op-playground", "scripts")
	if _, err := os.Stat(scriptsDir); err != nil {
		scriptsDir = filepath.Join(".", "scripts")
	}
	cfg.ScriptsDir = scriptsDir

	envVars := []string{
		fmt.Sprintf("OP_PG_L1_RPC=http://localhost:%d", l1Port),
		"OP_PG_DEV_PRIVKEY=" + acct.PrivateKey,
		"OP_PG_DEV_ADDR=" + acct.Address,
	}
	if owner, ok := dgfOwnerKey(); ok {
		envVars = append(envVars,
			"OP_PG_OWNER_PRIVKEY="+owner.PrivateKey,
			"OP_PG_OWNER_ADDR="+owner.Address,
		)
	}
	if g, ok := guardianKey(); ok {
		envVars = append(envVars,
			"OP_PG_GUARDIAN_PRIVKEY="+g.PrivateKey,
			"OP_PG_GUARDIAN_ADDR="+g.Address,
		)
	}
	if len(chains) == 1 {
		envVars = append(envVars, fmt.Sprintf("OP_PG_L2_RPC=http://localhost:%d", l2PortBase))
	} else {
		for i, chain := range chains {
			envVars = append(envVars, fmt.Sprintf("OP_PG_%s_RPC=http://localhost:%d", chain.Name, l2PortBase+i))
		}
		envVars = append(envVars, fmt.Sprintf("OP_PG_L2_RPC=http://localhost:%d", l2PortBase))
	}
	// Path to packages/contracts-bedrock so forge-script wrappers can find it
	// regardless of where the binary was launched from.
	if cwd, err := os.Getwd(); err == nil {
		// Walk up until we find a sibling "packages/contracts-bedrock".
		dir := cwd
		for i := 0; i < 6; i++ {
			candidate := filepath.Join(dir, "packages", "contracts-bedrock")
			if _, err := os.Stat(candidate); err == nil {
				envVars = append(envVars, "OP_PG_CONTRACTS_DIR="+candidate)
				break
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	// L1 contract addresses — useful for cast scripts that touch the dispute system.
	for _, chain := range chains {
		c := chain.L1Contracts
		prefix := "OP_PG"
		if len(chains) > 1 {
			prefix = "OP_PG_" + chain.Name
		}
		envVars = append(envVars,
			fmt.Sprintf("%s_SYSTEM_CONFIG=%s", prefix, c.SystemConfig.Hex()),
			fmt.Sprintf("%s_DGF=%s", prefix, c.DisputeGameFactory.Hex()),
			fmt.Sprintf("%s_PORTAL=%s", prefix, c.OptimismPortal.Hex()),
			fmt.Sprintf("%s_L1_BRIDGE=%s", prefix, c.L1StandardBridge.Hex()),
		)
	}
	cfg.EnvVars = envVars

	return cfg
}

func printEndpoints(w io.Writer, cfg server.Config) {
	fmt.Fprintf(w, "\n--- Endpoints ---\n")
	fmt.Fprintf(w, "Dashboard:  http://%s\n", cfg.UIAddr)
	for _, p := range cfg.Proxies {
		fmt.Fprintf(w, "%-10s  http://%s  (ws://%s)\n", p.Name+":", p.ListenAddr, p.ListenAddr)
	}
	fmt.Fprintf(w, "-----------------\n\n")
}

// dgfOwnerKey derives the L1ProxyAdminOwner devkey for L1 chain 900 — the
// account that owns DisputeGameFactory in the Minimal preset. Returns ok=false
// if derivation fails.
func dgfOwnerKey() (state.FundedAccount, bool) {
	hd, err := devkeys.NewMnemonicDevKeys(devkeys.TestMnemonic)
	if err != nil {
		return state.FundedAccount{}, false
	}
	const l1ChainID = 900
	key := devkeys.L1ProxyAdminOwnerRole.Key(big.NewInt(l1ChainID))
	addr, err := hd.Address(key)
	if err != nil {
		return state.FundedAccount{}, false
	}
	priv, err := hd.Secret(key)
	if err != nil {
		return state.FundedAccount{}, false
	}
	return state.FundedAccount{
		Address:    addr.Hex(),
		PrivateKey: "0x" + common.Bytes2Hex(crypto.FromECDSA(priv)),
	}, true
}

// guardianKey derives the SuperchainConfigGuardian devkey for L1 chain 900 —
// the account that can flip the AnchorStateRegistry's respected game type.
func guardianKey() (state.FundedAccount, bool) {
	hd, err := devkeys.NewMnemonicDevKeys(devkeys.TestMnemonic)
	if err != nil {
		return state.FundedAccount{}, false
	}
	const l1ChainID = 900
	key := devkeys.SuperchainConfigGuardianKey.Key(big.NewInt(l1ChainID))
	addr, err := hd.Address(key)
	if err != nil {
		return state.FundedAccount{}, false
	}
	priv, err := hd.Secret(key)
	if err != nil {
		return state.FundedAccount{}, false
	}
	return state.FundedAccount{
		Address:    addr.Hex(),
		PrivateKey: "0x" + common.Bytes2Hex(crypto.FromECDSA(priv)),
	}, true
}

func fundedAccount() (state.FundedAccount, error) {
	hd, err := devkeys.NewMnemonicDevKeys(devkeys.TestMnemonic)
	if err != nil {
		return state.FundedAccount{}, fmt.Errorf("dev keys: %w", err)
	}
	const funderIndex = 10_000
	key := devkeys.UserKey(funderIndex)
	addr, err := hd.Address(key)
	if err != nil {
		return state.FundedAccount{}, err
	}
	priv, err := hd.Secret(key)
	if err != nil {
		return state.FundedAccount{}, err
	}
	return state.FundedAccount{
		Address:    addr.Hex(),
		PrivateKey: "0x" + common.Bytes2Hex(crypto.FromECDSA(priv)),
	}, nil
}

func newMinimalSystem(t *harness.TestingT) (sys *presets.Minimal, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = harness.RecoverFailure(r)
		}
	}()
	return presets.NewMinimal(t, presets.WithTimeTravel()), nil
}

func newInteropSystem(t *harness.TestingT) (sys *presets.TwoL2SupernodeInterop, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = harness.RecoverFailure(r)
		}
	}()
	const interopDelay = uint64(2)
	return presets.NewTwoL2SupernodeInterop(t, interopDelay,
		presets.WithSuggestedInteropActivationOffset(interopDelay),
		presets.WithTimeTravel(),
	), nil
}
