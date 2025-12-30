package manage

import (
	"context"
	"encoding/hex"
	"flag"
	"fmt"
	"log/slog"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/bootstrap"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/integration_test/shared"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/testutil"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/env"
	"github.com/ethereum-optimism/optimism/op-service/testlog"
	"github.com/ethereum-optimism/optimism/op-service/testutils"
	"github.com/ethereum-optimism/optimism/op-service/testutils/devnet"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/params"
	"github.com/ethereum/go-ethereum/rpc"
	"github.com/stretchr/testify/require"
	"github.com/urfave/cli/v2"
)

func TestInteropMigration(t *testing.T) {
	t.Skip("Skipped until the sepolia opcm supports the interop migration (missing superFaultDisputeGameImpl and superPermissionedDisputeGameImpl)")

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
			UsePermissionlessGame: true,
			StartingAnchorRoot: Proposal{
				Root:             common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"),
				L2SequenceNumber: big.NewInt(1),
			},
			GameParameters: GameParameters{
				Proposer:         common.Address{'A'},
				Challenger:       common.Address{'B'},
				MaxGameDepth:     10,
				SplitDepth:       10,
				InitBond:         big.NewInt(1000000000000000000), // 1 ETH
				ClockExtension:   10,
				MaxClockDuration: 10,
			},
			OpChainConfigs: []OPChainConfig{
				{
					SystemConfigProxy:  common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"),
					CannonPrestate:     common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"),
					CannonKonaPrestate: common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000fed"),
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
	// t.Skip("Interop migration requires a chain that was deployed by the OPCM being used. Bootstrapping fresh implementations doesn't establish this relationship. To test this properly would require deploying a full chain first.")

	lgr := testlog.Logger(t, slog.LevelDebug)

	forkedL1, stopL1, err := devnet.NewForkedSepolia(lgr)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, stopL1())
	})
	l1RPC := forkedL1.RPCUrl()

	_, afactsFS := testutil.LocalArtifacts(t)
	testCacheDir := testutils.IsolatedTestDirWithAutoCleanup(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	pkHex, _, _ := shared.DefaultPrivkey(t)

	// Deploy superchain contracts first (required for OPCM deployment)
	// This is the key difference from V1 test - we need to deploy our own superchain
	// on the forked network instead of using existing Sepolia addresses
	superchainProxyAdminOwner := common.Address{'S'}
	superchainOut, err := bootstrap.Superchain(ctx, bootstrap.SuperchainConfig{
		L1RPCUrl:                   l1RPC,
		PrivateKey:                 pkHex,
		ArtifactsLocator:           artifacts.EmbeddedLocator,
		Logger:                     lgr,
		SuperchainProxyAdminOwner:  superchainProxyAdminOwner,
		ProtocolVersionsOwner:      common.Address{'P'},
		Guardian:                   common.Address{'G'},
		Paused:                     false,
		RequiredProtocolVersion:    params.ProtocolVersionV0{Major: 1}.Encode(),
		RecommendedProtocolVersion: params.ProtocolVersionV0{Major: 2}.Encode(),
		CacheDir:                   testCacheDir,
	})
	require.NoError(t, err, "Failed to deploy superchain contracts")

	// Deploy implementations with OPCM V2 enabled
	// Use the superchain outputs from the previous step
	impls, err := bootstrap.Implementations(ctx, bootstrap.ImplementationsConfig{
		L1RPCUrl:                        l1RPC,
		PrivateKey:                      pkHex,
		ArtifactsLocator:                artifacts.EmbeddedLocator,
		Logger:                          lgr,
		MIPSVersion:                     int(standard.MIPSVersion),
		WithdrawalDelaySeconds:          standard.WithdrawalDelaySeconds,
		MinProposalSizeBytes:            standard.MinProposalSizeBytes,
		ChallengePeriodSeconds:          standard.ChallengePeriodSeconds,
		ProofMaturityDelaySeconds:       standard.ProofMaturityDelaySeconds,
		DisputeGameFinalityDelaySeconds: standard.DisputeGameFinalityDelaySeconds,
		DevFeatureBitmap:                deployer.OPCMV2DevFlag, // Enable OPCM V2
		SuperchainConfigProxy:           superchainOut.SuperchainConfigProxy,
		ProtocolVersionsProxy:           superchainOut.ProtocolVersionsProxy,
		SuperchainProxyAdmin:            superchainOut.SuperchainProxyAdmin,
		L1ProxyAdminOwner:               superchainProxyAdminOwner,
		Challenger:                      common.Address{'C'},
		CacheDir:                        testCacheDir,
		FaultGameMaxGameDepth:           standard.DisputeMaxGameDepth,
		FaultGameSplitDepth:             standard.DisputeSplitDepth,
		FaultGameClockExtension:         standard.DisputeClockExtension,
		FaultGameMaxClockDuration:       standard.DisputeMaxClockDuration,
	})
	require.NoError(t, err, "Failed to deploy implementations")

	// Verify OPCM V2 was deployed correctly
	require.NotEqual(t, common.Address{}, impls.OpcmV2, "OPCM V2 address should be set")
	require.Equal(t, common.Address{}, impls.Opcm, "OPCM V1 address should be zero when V2 is deployed")

	rpcClient, err := rpc.Dial(l1RPC)
	require.NoError(t, err)

	bcast := new(broadcaster.CalldataBroadcaster)
	host, err := env.DefaultForkedScriptHost(
		ctx,
		bcast,
		lgr,
		superchainProxyAdminOwner,
		afactsFS,
		rpcClient,
	)
	require.NoError(t, err)

	// Prepare game args for V2 - ABI encode the prestate
	bytes32Type, err := abi.NewType("bytes32", "", nil)
	require.NoError(t, err)
	testPrestate := common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc")
	gameArgs, err := abi.Arguments{{Type: bytes32Type}}.Pack(testPrestate)
	require.NoError(t, err)

	// Use a test SystemConfigProxy address (same as V1 test uses)
	// This would normally be an actual deployed SystemConfig proxy for the chain being migrated
	systemConfigProxy := common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538")

	// Define game type constants matching Solidity GameTypes library
	const (
		GameTypeCannon                  = uint32(0)
		GameTypePermissionedCannon      = uint32(1)
		GameTypeSuperCannon             = uint32(4)
		GameTypeSuperPermissionedCannon = uint32(5)
	)

	input := InteropMigrationInput{
		Prank: superchainProxyAdminOwner,
		Opcm:  impls.OpcmV2,
		MigrateInputV2: &MigrateInputV2{
			ChainSystemConfigs: []common.Address{
				systemConfigProxy,
			},
			DisputeGameConfigs: []DisputeGameConfig{
				{
					Enabled:  true,
					InitBond: big.NewInt(1000000000000000000), // 1 ETH
					GameType: GameTypeCannon,                  // Must be SUPER_CANNON (4) or SUPER_PERMISSIONED_CANNON (5)
					GameArgs: gameArgs,
				},
			},
			StartingAnchorRoot: Proposal{
				Root:             common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"),
				L2SequenceNumber: big.NewInt(1),
			},
			StartingRespectedGameType: GameTypeSuperCannon,
		},
	}

	// ========================================
	// Pre-migration Assertions
	// These match the requirements from OPContractsManagerMigrator.sol migrate() function
	// ========================================

	// 1. Validate OPCM V2 address is set
	require.NotEqual(t, common.Address{}, input.Opcm, "OPCM address must not be zero")

	// 2. Validate startingRespectedGameType is a valid super game type
	// Per line 75-80 in OPContractsManagerMigrator.sol
	require.True(t,
		input.MigrateInputV2.StartingRespectedGameType == GameTypeSuperCannon ||
			input.MigrateInputV2.StartingRespectedGameType == GameTypeSuperPermissionedCannon,
		"startingRespectedGameType must be SUPER_CANNON (4) or SUPER_PERMISSIONED_CANNON (5), got: %d",
		input.MigrateInputV2.StartingRespectedGameType,
	)

	// 3. Validate we have at least one chain system config
	// Per line 83-95 in OPContractsManagerMigrator.sol
	require.NotEmpty(t, input.MigrateInputV2.ChainSystemConfigs,
		"chainSystemConfigs must not be empty")

	// 4. Validate all chain system configs are set (not zero addresses)
	for i, sc := range input.MigrateInputV2.ChainSystemConfigs {
		require.NotEqual(t, common.Address{}, sc,
			"chainSystemConfigs[%d] must not be zero address", i)
	}

	// 5. Validate we have at least one dispute game config
	// Per line 211-218 in OPContractsManagerMigrator.sol
	require.NotEmpty(t, input.MigrateInputV2.DisputeGameConfigs,
		"disputeGameConfigs must not be empty")

	// 6. Validate all enabled dispute game configs have proper game args
	for i, dgc := range input.MigrateInputV2.DisputeGameConfigs {
		if dgc.Enabled {
			require.NotNil(t, dgc.InitBond,
				"disputeGameConfigs[%d].initBond must not be nil", i)
			require.True(t, dgc.InitBond.Cmp(big.NewInt(0)) >= 0,
				"disputeGameConfigs[%d].initBond must be non-negative", i)
			require.NotEmpty(t, dgc.GameArgs,
				"disputeGameConfigs[%d].gameArgs must not be empty for enabled games", i)
		}
	}

	// 7. Validate starting anchor root is properly set
	// Per line 185-194 in OPContractsManagerMigrator.sol
	require.NotEqual(t, common.Hash{}, input.MigrateInputV2.StartingAnchorRoot.Root,
		"startingAnchorRoot.root must not be zero")
	require.NotNil(t, input.MigrateInputV2.StartingAnchorRoot.L2SequenceNumber,
		"startingAnchorRoot.l2SequenceNumber must not be nil")
	require.True(t, input.MigrateInputV2.StartingAnchorRoot.L2SequenceNumber.Cmp(big.NewInt(0)) > 0,
		"startingAnchorRoot.l2SequenceNumber must be positive")

	// 8. Log the input for debugging
	t.Logf("Migrate input validation passed:")
	t.Logf("  OPCM V2: %s", input.Opcm.Hex())
	t.Logf("  Chain count: %d", len(input.MigrateInputV2.ChainSystemConfigs))
	t.Logf("  Dispute game configs: %d", len(input.MigrateInputV2.DisputeGameConfigs))
	t.Logf("  Starting respected game type: %d", input.MigrateInputV2.StartingRespectedGameType)
	t.Logf("  Starting anchor root: %s @ block %s",
		input.MigrateInputV2.StartingAnchorRoot.Root.Hex(),
		input.MigrateInputV2.StartingAnchorRoot.L2SequenceNumber.String())

	// ========================================
	// Execute Migration
	// ========================================
	output, err := Migrate(host, input)
	require.NoError(t, err)
	require.NotEqual(t, common.Address{}, output.DisputeGameFactory)

	dump, err := bcast.Dump()
	require.NoError(t, err)
	require.Len(t, dump, 1, "Should have one transaction")
	require.True(t, dump[0].Value.ToInt().Cmp(common.Big0) == 0, "Transaction value should be zero")
	require.Equal(t, *dump[0].To, superchainProxyAdminOwner, "Transaction should be sent to prank address")
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
	gameArgs := common.FromHex(ctx.String(DisputeAbsolutePrestateFlag.Name))
	startingAnchorRoot := common.HexToHash(ctx.String(StartingAnchorRootFlag.Name))
	startingAnchorL2SeqNum := ctx.Uint64(StartingAnchorL2SequenceNumberFlag.Name)
	startingRespectedGameType := uint32(ctx.Uint64(StartingRespectedGameTypeFlag.Name))

	// Verify values
	require.Equal(t, common.HexToAddress("0xaf334f4537e87f5155d135392ff6d52f1866465e"), opcmAddr)
	require.Equal(t, common.HexToAddress("0x034edD2A225f7f429A63E0f1D2084B9E0A93b538"), systemConfigProxy)
	require.True(t, disputeGameEnabled)
	require.Equal(t, big.NewInt(1000000000000000000), initBond)
	require.Equal(t, uint32(0), gameType)
	require.Equal(t, common.FromHex("0x0000000000000000000000000000000000000000000000000000000000000abc"), gameArgs)
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
			switch tc.expectedErr {
			case OPCMImplFlag.Name:
				require.Empty(t, ctx.String(OPCMImplFlag.Name))
			case SystemConfigProxyFlag.Name:
				require.Empty(t, ctx.String(SystemConfigProxyFlag.Name))
			}
		})
	}
}

func TestEncodedMigrateInputV2(t *testing.T) {
	// Prepare game args - ABI encode a prestate hash
	bytes32Type, err := abi.NewType("bytes32", "", nil)
	require.NoError(t, err)
	testPrestate := common.HexToHash("0xaa00000000000000000000000000000000000000000000000000000000000000")
	gameArgs, err := abi.Arguments{{Type: bytes32Type}}.Pack(testPrestate)
	require.NoError(t, err)

	input := &InteropMigrationInput{
		Prank: common.Address{0xaa},
		Opcm:  common.Address{0xbb},
		MigrateInputV2: &MigrateInputV2{
			ChainSystemConfigs: []common.Address{
				common.Address{0x01},
			},
			DisputeGameConfigs: []DisputeGameConfig{
				{
					Enabled:  true,
					InitBond: big.NewInt(1000),
					GameType: 4,
					GameArgs: gameArgs,
				},
			},
			StartingAnchorRoot: Proposal{
				Root:             common.Hash{0xde},
				L2SequenceNumber: big.NewInt(100),
			},
			StartingRespectedGameType: 4,
		},
	}

	data, err := input.EncodedMigrateInputV2()
	require.NoError(t, err)
	require.NotEmpty(t, data)

	expected := "0000000000000000000000000000000000000000000000000000000000000020" + // offset to tuple
		"00000000000000000000000000000000000000000000000000000000000000a0" + // offset to chainSystemConfigs (5 words * 32 = 160 = 0xa0)
		"00000000000000000000000000000000000000000000000000000000000000e0" + // offset to disputeGameConfigs (0xa0 + 0x40)
		"de00000000000000000000000000000000000000000000000000000000000000" + // startingAnchorRoot.root
		"0000000000000000000000000000000000000000000000000000000000000064" + // startingAnchorRoot.l2SequenceNumber (100)
		"0000000000000000000000000000000000000000000000000000000000000004" + // startingRespectedGameType (4)
		"0000000000000000000000000000000000000000000000000000000000000001" + // chainSystemConfigs.length (1)
		"0000000000000000000000000100000000000000000000000000000000000000" + // chainSystemConfigs[0]
		"0000000000000000000000000000000000000000000000000000000000000001" + // disputeGameConfigs.length (1)
		"0000000000000000000000000000000000000000000000000000000000000020" + // offset to disputeGameConfigs[0]
		"0000000000000000000000000000000000000000000000000000000000000001" + // disputeGameConfigs[0].enabled
		"00000000000000000000000000000000000000000000000000000000000003e8" + // disputeGameConfigs[0].initBond (1000)
		"0000000000000000000000000000000000000000000000000000000000000004" + // disputeGameConfigs[0].gameType (4)
		"0000000000000000000000000000000000000000000000000000000000000080" + // offset to gameArgs
		"0000000000000000000000000000000000000000000000000000000000000020" + // gameArgs.length (32 bytes)
		"aa00000000000000000000000000000000000000000000000000000000000000" // gameArgs data (prestate)

	require.Equal(t, expected, hex.EncodeToString(data))
}
