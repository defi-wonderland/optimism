package cli

import (
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/upgrade/embedded"
	"github.com/ethereum-optimism/optimism/op-service/testlog"
	"github.com/ethereum-optimism/optimism/op-service/testutils/devnet"
	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"
)

func TestManageAddGameTypeV2_CLI(t *testing.T) {
	t.Run("missing required flag --config", func(t *testing.T) {
		runner := NewCLITestRunnerWithNetwork(t)
		runner.ExpectErrorContains(t, []string{
			"manage", "add-game-type-v2",
			"--l1-rpc-url", runner.l1RPC,
		}, nil, "missing required flag: config")
	})

	t.Run("missing required flag --l1-rpc-url", func(t *testing.T) {
		runner := NewCLITestRunner(t)
		workDir := runner.GetWorkDir()
		configFile := filepath.Join(workDir, "config.json")

		// Create a minimal valid config file
		config := embedded.UpgradeOPChainInput{
			Prank: common.Address{0x01},
			Opcm:  common.Address{0x02},
			UpgradeInputV2: &embedded.UpgradeInputV2{
				SystemConfig:       common.Address{0x03},
				DisputeGameConfigs: []embedded.DisputeGameConfig{},
				ExtraInstructions:  []embedded.ExtraInstruction{},
			},
		}
		configData, err := json.Marshal(config)
		require.NoError(t, err)
		require.NoError(t, os.WriteFile(configFile, configData, 0o644))

		runner.ExpectErrorContains(t, []string{
			"manage", "add-game-type-v2",
			"--config", configFile,
		}, nil, "missing required flag: l1-rpc-url")
	})

	t.Run("invalid config file path", func(t *testing.T) {
		runner := NewCLITestRunnerWithNetwork(t)
		runner.ExpectErrorContains(t, []string{
			"manage", "add-game-type-v2",
			"--config", "/nonexistent/path/config.json",
			"--l1-rpc-url", runner.l1RPC,
		}, nil, "failed to read config file")
	})

	t.Run("invalid JSON config file", func(t *testing.T) {
		runner := NewCLITestRunnerWithNetwork(t)
		workDir := runner.GetWorkDir()
		configFile := filepath.Join(workDir, "invalid_config.json")

		// Write invalid JSON
		require.NoError(t, os.WriteFile(configFile, []byte("{invalid json}"), 0o644))

		runner.ExpectErrorContains(t, []string{
			"manage", "add-game-type-v2",
			"--config", configFile,
			"--l1-rpc-url", runner.l1RPC,
		}, nil, "failed to upgrade")
	})

	t.Run("config file missing required fields", func(t *testing.T) {
		runner := NewCLITestRunnerWithNetwork(t)
		workDir := runner.GetWorkDir()
		configFile := filepath.Join(workDir, "incomplete_config.json")

		// Create config missing prank or opcm
		config := map[string]interface{}{
			"prank": common.Address{0x01}.Hex(),
			// Missing opcm
		}
		configData, err := json.Marshal(config)
		require.NoError(t, err)
		require.NoError(t, os.WriteFile(configFile, configData, 0o644))

		runner.ExpectErrorContains(t, []string{
			"manage", "add-game-type-v2",
			"--config", configFile,
			"--l1-rpc-url", runner.l1RPC,
		}, nil, "failed to upgrade")
	})
}

func TestManageAddGameTypeV2_Integration(t *testing.T) {
	lgr := testlog.Logger(t, slog.LevelDebug)
	forkedL1, stopL1, err := devnet.NewForkedSepolia(lgr)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, stopL1())
	})

	runner := NewCLITestRunnerWithNetwork(t, WithL1RPC(forkedL1.RPCUrl()))
	workDir := runner.GetWorkDir()

	// op-sepolia values for testing
	l1ProxyAdminOwner := common.HexToAddress("0x1Eb2fFc903729a0F03966B917003800b145F56E2")
	systemConfigProxy := common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538")

	// Get OPCM V2 address from standard
	opcmV2, err := standard.OPCMImplAddressFor(11155111, standard.ContractsV500Tag)
	require.NoError(t, err)

	testConfig := embedded.UpgradeOPChainInput{
		Prank: l1ProxyAdminOwner,
		Opcm:  opcmV2,
		UpgradeInputV2: &embedded.UpgradeInputV2{
			SystemConfig: systemConfigProxy,
			DisputeGameConfigs: []embedded.DisputeGameConfig{
				{
					Enabled:  true,
					InitBond: big.NewInt(1000000000000000000), // 1 ETH
					GameType: embedded.GameTypeCannon,
					GameArgs: []byte{},
				},
			},
			ExtraInstructions: []embedded.ExtraInstruction{
				{
					Key:  "PermittedProxyDeployment",
					Data: []byte("DelayedWETH"),
				},
			},
		},
	}

	configFile := filepath.Join(workDir, "add_game_type_v2_config.json")
	outputFile := filepath.Join(workDir, "add_game_type_v2_output.json")

	configData, err := json.MarshalIndent(testConfig, "", "  ")
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(configFile, configData, 0o644))

	// Run the CLI command
	output := runner.ExpectSuccessWithNetwork(t, []string{
		"manage", "add-game-type-v2",
		"--config", configFile,
		"--outfile", outputFile,
	}, nil)

	t.Logf("Command output (logs):\n%s", output)

	// Verify output file was created
	require.FileExists(t, outputFile)
	data, err := os.ReadFile(outputFile)
	require.NoError(t, err)

	var dump []broadcaster.CalldataDump
	require.NoError(t, json.Unmarshal(data, &dump))

	t.Logf("Add game type v2 generated calldata: %s", string(data))

	// Verify the calldata structure
	require.Len(t, dump, 1)
	require.Equal(t, l1ProxyAdminOwner.Hex(), dump[0].To.Hex(), "calldata should be sent to prank address")

	// Verify the calldata has the correct function selector for opcm.upgrade
	// The selector for upgrade(address,bytes) is 0xff2dd5a1
	dataHex := hex.EncodeToString(dump[0].Data)
	require.True(t, strings.HasPrefix(dataHex, "ff2dd5a1"),
		"calldata should have opcm.upgrade function selector ff2dd5a1, got: %s", dataHex[:8])
}
