package manage

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/testutil"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/env"
	"github.com/ethereum-optimism/optimism/op-service/testlog"
	"github.com/ethereum-optimism/optimism/op-service/testutils/devnet"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rpc"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

func TestInteropMigration(t *testing.T) {
	t.Skip("Skipped until the sepolia opcm supports the interop migration")

	lgr := testlog.Logger(t, slog.LevelDebug)

	forkedL1, stopL1, err := devnet.NewForkedSepolia(lgr)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, stopL1())
	})
	l1RPC := forkedL1.RPCUrl()

	_, afactsFS := testutil.LocalArtifacts(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	rpcClient, err := rpc.Dial(l1RPC)
	require.NoError(t, err)

	bcast := new(broadcaster.CalldataBroadcaster)
	host, err := env.DefaultForkedScriptHost(
		ctx,
		bcast,
		lgr,
		common.Address{'D'},
		afactsFS,
		rpcClient,
	)
	require.NoError(t, err)

	pao := common.HexToAddress("0x1Eb2fFc903729a0F03966B917003800b145F56E2")
	input := InteropMigrationInput{
		Prank: pao,
		Opcm:  common.HexToAddress("0xaf334f4537e87f5155d135392ff6d52f1866465e"),
		MigrateInputV1: &MigrateInputV1{
			UsePermissionlessGame:          true,
			StartingAnchorL2SequenceNumber: big.NewInt(1),
			Proposer:                       common.Address{'A'},
			Challenger:                     common.Address{'B'},
			MaxGameDepth:                   10,
			SplitDepth:                     10,
			InitBond:                       big.NewInt(1000000000000000000), // 1 ETH
			ClockExtension:                 10,
			MaxClockDuration:               10,
			OpChainConfigs: []OPChainConfig{
				{
					SystemConfigProxy: common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"),
					CannonPrestate:    common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"),
				},
			},
		},
	}
	output, err := Migrate(host, input)
	require.NoError(t, err)
	require.NotEqual(t, common.Address{}, output.DisputeGameFactory)

	dump, err := bcast.Dump()
	require.NoError(t, err)
	require.True(t, dump[0].Value.ToInt().Cmp(common.Big0) == 0)
	require.Equal(t, *dump[0].To, pao)
}

func TestInteropMigrationV2(t *testing.T) {
	t.Skip("Skipped until the sepolia opcm supports the interop migration v2")

	lgr := testlog.Logger(t, slog.LevelDebug)

	forkedL1, stopL1, err := devnet.NewForkedSepolia(lgr)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, stopL1())
	})
	l1RPC := forkedL1.RPCUrl()

	_, afactsFS := testutil.LocalArtifacts(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	rpcClient, err := rpc.Dial(l1RPC)
	require.NoError(t, err)

	bcast := new(broadcaster.CalldataBroadcaster)
	host, err := env.DefaultForkedScriptHost(
		ctx,
		bcast,
		lgr,
		common.Address{'D'},
		afactsFS,
		rpcClient,
	)
	require.NoError(t, err)

	pao := common.HexToAddress("0x1Eb2fFc903729a0F03966B917003800b145F56E2")
	input := InteropMigrationInput{
		Prank: pao,
		Opcm:  common.HexToAddress("0xaf334f4537e87f5155d135392ff6d52f1866465e"),
		MigrateInputV2: &MigrateInputV2{
			ChainSystemConfigs: []common.Address{
				common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"),
			},
			DisputeGameConfigs: []DisputeGameConfig{
				{
					Enabled:  true,
					InitBond: big.NewInt(1000000000000000000), // 1 ETH
					GameType: 0,                               // Cannon
					GameArgs: common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"),
				},
			},
			StartingAnchorRoot: Proposal{
				Root:           common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"),
				SequenceNumber: big.NewInt(1),
			},
			StartingRespectedGameType: 0, // Cannon
		},
	}
	output, err := Migrate(host, input)
	require.NoError(t, err)
	require.NotEqual(t, common.Address{}, output.DisputeGameFactory)

	dump, err := bcast.Dump()
	require.NoError(t, err)
	require.True(t, dump[0].Value.ToInt().Cmp(common.Big0) == 0)
	require.Equal(t, *dump[0].To, pao)
}

func TestMigrateCLI_V1Flags(t *testing.T) {
	app := cli.NewApp()
	flagSet := flag.NewFlagSet("test-migrate-v1", flag.ContinueOnError)

	// Set V1-specific flags
	flagSet.String(OPCMImplFlag.Name, "0xaf334f4537e87f5155d135392ff6d52f1866465e", "doc")
	flagSet.String(SystemConfigProxyFlag.Name, "0x034edD2A225f7f429A63E0f1D2084B9E0A93b538", "doc")
	flagSet.Bool(PermissionlessFlag.Name, true, "doc")
	flagSet.String(ProposerFlag.Name, "0x1111111111111111111111111111111111111111", "doc")
	flagSet.String(ChallengerFlag.Name, "0x2222222222222222222222222222222222222222", "doc")
	flagSet.String(StartingAnchorRootFlag.Name, "0x0000000000000000000000000000000000000000000000000000000000000abc", "doc")
	flagSet.Uint64(StartingAnchorL2SequenceNumberFlag.Name, 1, "doc")
	flagSet.Uint64(DisputeMaxGameDepthFlag.Name, 73, "doc")
	flagSet.Uint64(DisputeSplitDepthFlag.Name, 30, "doc")
	flagSet.String(InitialBondFlag.Name, "1000000000000000000", "doc")
	flagSet.Uint64(DisputeClockExtensionFlag.Name, 10800, "doc")
	flagSet.Uint64(DisputeMaxClockDurationFlag.Name, 302400, "doc")
	flagSet.String(DisputeAbsolutePrestateCannonFlag.Name, "0x0000000000000000000000000000000000000000000000000000000000000def", "doc")
	flagSet.String(DisputeAbsolutePrestateCannonKonaFlag.Name, "0x0000000000000000000000000000000000000000000000000000000000000fed", "doc")

	ctx := cli.NewContext(app, flagSet, nil)

	// Parse V1 flags
	opcmAddr := common.HexToAddress(ctx.String(OPCMImplFlag.Name))
	systemConfigProxy := common.HexToAddress(ctx.String(SystemConfigProxyFlag.Name))
	permissionless := ctx.Bool(PermissionlessFlag.Name)
	proposer := common.HexToAddress(ctx.String(ProposerFlag.Name))
	challenger := common.HexToAddress(ctx.String(ChallengerFlag.Name))
	startingAnchorRoot := common.HexToHash(ctx.String(StartingAnchorRootFlag.Name))
	startingAnchorL2SeqNum := ctx.Uint64(StartingAnchorL2SequenceNumberFlag.Name)
	maxGameDepth := ctx.Uint64(DisputeMaxGameDepthFlag.Name)
	splitDepth := ctx.Uint64(DisputeSplitDepthFlag.Name)
	initBondStr := ctx.String(InitialBondFlag.Name)
	initBond, ok := new(big.Int).SetString(initBondStr, 10)
	require.True(t, ok)
	clockExtension := ctx.Uint64(DisputeClockExtensionFlag.Name)
	maxClockDuration := ctx.Uint64(DisputeMaxClockDurationFlag.Name)
	cannonPrestate := common.HexToHash(ctx.String(DisputeAbsolutePrestateCannonFlag.Name))
	cannonKonaPrestate := common.HexToHash(ctx.String(DisputeAbsolutePrestateCannonKonaFlag.Name))

	// Verify values
	require.Equal(t, common.HexToAddress("0xaf334f4537e87f5155d135392ff6d52f1866465e"), opcmAddr)
	require.Equal(t, common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"), systemConfigProxy)
	require.True(t, permissionless)
	require.Equal(t, common.HexToAddress("0x1111111111111111111111111111111111111111"), proposer)
	require.Equal(t, common.HexToAddress("0x2222222222222222222222222222222222222222"), challenger)
	require.Equal(t, common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"), startingAnchorRoot)
	require.Equal(t, uint64(1), startingAnchorL2SeqNum)
	require.Equal(t, uint64(73), maxGameDepth)
	require.Equal(t, uint64(30), splitDepth)
	require.Equal(t, big.NewInt(1000000000000000000), initBond)
	require.Equal(t, uint64(10800), clockExtension)
	require.Equal(t, uint64(302400), maxClockDuration)
	require.Equal(t, common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"), cannonPrestate)
	require.Equal(t, common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000fed"), cannonKonaPrestate)
}

func TestMigrateCLI_V2Flags(t *testing.T) {
	app := cli.NewApp()
	flagSet := flag.NewFlagSet("test-migrate-v2", flag.ContinueOnError)

	// Set V2-specific flags
	flagSet.String(OPCMImplFlag.Name, "0xaf334f4537e87f5155d135392ff6d52f1866465e", "doc")
	flagSet.String(SystemConfigProxyFlag.Name, "0x034edD2A225f7f429A63E0f1D2084B9E0A93b538", "doc")
	flagSet.Bool(DisputeGameEnabledFlag.Name, true, "doc")
	flagSet.String(InitialBondFlag.Name, "1000000000000000000", "doc")
	flagSet.Uint64(DisputeGameTypeFlag.Name, 0, "doc")
	flagSet.String(DisputeAbsolutePrestateFlag.Name, "0x0000000000000000000000000000000000000000000000000000000000000abc", "doc")
	flagSet.String(StartingAnchorRootFlag.Name, "0x0000000000000000000000000000000000000000000000000000000000000def", "doc")
	flagSet.Uint64(StartingAnchorL2SequenceNumberFlag.Name, 1, "doc")
	flagSet.Uint64(StartingRespectedGameTypeFlag.Name, 0, "doc")

	ctx := cli.NewContext(app, flagSet, nil)

	// Parse V2 flags
	opcmAddr := common.HexToAddress(ctx.String(OPCMImplFlag.Name))
	systemConfigProxy := common.HexToAddress(ctx.String(SystemConfigProxyFlag.Name))
	disputeGameEnabled := ctx.Bool(DisputeGameEnabledFlag.Name)
	initBondStr := ctx.String(InitialBondFlag.Name)
	initBond, ok := new(big.Int).SetString(initBondStr, 10)
	require.True(t, ok)
	gameType := uint32(ctx.Uint64(DisputeGameTypeFlag.Name))
	gameArgs := common.HexToHash(ctx.String(DisputeAbsolutePrestateFlag.Name))
	startingAnchorRoot := common.HexToHash(ctx.String(StartingAnchorRootFlag.Name))
	startingAnchorL2SeqNum := ctx.Uint64(StartingAnchorL2SequenceNumberFlag.Name)
	startingRespectedGameType := uint32(ctx.Uint64(StartingRespectedGameTypeFlag.Name))

	// Verify values
	require.Equal(t, common.HexToAddress("0xaf334f4537e87f5155d135392ff6d52f1866465e"), opcmAddr)
	require.Equal(t, common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"), systemConfigProxy)
	require.True(t, disputeGameEnabled)
	require.Equal(t, big.NewInt(1000000000000000000), initBond)
	require.Equal(t, uint32(0), gameType)
	require.Equal(t, common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"), gameArgs)
	require.Equal(t, common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"), startingAnchorRoot)
	require.Equal(t, uint64(1), startingAnchorL2SeqNum)
	require.Equal(t, uint32(0), startingRespectedGameType)
}

func TestMigrateCLI_MissingRequiredFlags(t *testing.T) {
	testCases := []struct {
		name        string
		setupFlags  func(*flag.FlagSet)
		expectedErr string
	}{
		{
			name: "missing opcm impl",
			setupFlags: func(fs *flag.FlagSet) {
				fs.String(SystemConfigProxyFlag.Name, "0x034edD2A225f7f429A63E0f1D2084B9E0A93b538", "doc")
			},
			expectedErr: OPCMImplFlag.Name,
		},
		{
			name: "missing system config proxy",
			setupFlags: func(fs *flag.FlagSet) {
				fs.String(OPCMImplFlag.Name, "0xaf334f4537e87f5155d135392ff6d52f1866465e", "doc")
			},
			expectedErr: SystemConfigProxyFlag.Name,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			app := cli.NewApp()
			flagSet := flag.NewFlagSet(fmt.Sprintf("test-%s", tc.name), flag.ContinueOnError)
			tc.setupFlags(flagSet)

			ctx := cli.NewContext(app, flagSet, nil)

			// Verify that the expected flag is not set
			if tc.expectedErr == OPCMImplFlag.Name {
				require.Empty(t, ctx.String(OPCMImplFlag.Name))
			} else if tc.expectedErr == SystemConfigProxyFlag.Name {
				require.Empty(t, ctx.String(SystemConfigProxyFlag.Name))
			}
		})
	}
}
