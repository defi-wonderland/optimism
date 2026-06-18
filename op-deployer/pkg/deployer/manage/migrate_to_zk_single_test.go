package manage

import (
	"context"
	"log/slog"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum-optimism/optimism/op-core/devfeatures"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/integration_test/shared"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/pipeline"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/testutil"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/upgrade/embedded"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/env"
	"github.com/ethereum-optimism/optimism/op-service/testlog"
	"github.com/ethereum-optimism/optimism/op-service/testutils"
	"github.com/ethereum-optimism/optimism/op-service/testutils/devnet"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rpc"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/require"
)

func validZKSingleParams() migrateToZKSingleParams {
	return migrateToZKSingleParams{
		Prank:                common.HexToAddress("0x000000000000000000000000000000000000aaaa"),
		Opcm:                 common.HexToAddress("0x000000000000000000000000000000000000bbbb"),
		SystemConfig:         common.HexToAddress("0x000000000000000000000000000000000000cccc"),
		AbsolutePrestate:     common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"),
		Verifier:             common.HexToAddress("0x000000000000000000000000000000000000bEEF"),
		MaxChallengeDuration: 7 * 24 * 60 * 60,
		MaxProveDuration:     3 * 24 * 60 * 60,
		InitBond:             big.NewInt(1e18),
		StartingAnchorRoot:   common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"),
		StartingAnchorL2Seq:  42,
	}
}

func TestBuildMigrateToZKSingleInput(t *testing.T) {
	t.Run("builds the full game config array with only ZK enabled", func(t *testing.T) {
		p := validZKSingleParams()
		in, err := buildMigrateToZKSingleInput(p)
		require.NoError(t, err)

		require.Equal(t, p.Prank, in.Prank)
		require.Equal(t, p.Opcm, in.Opcm)
		require.NotNil(t, in.UpgradeInputV2)
		require.Equal(t, p.SystemConfig, in.UpgradeInputV2.SystemConfig)

		cfgs := in.UpgradeInputV2.DisputeGameConfigs
		// The order must match validGameTypes in OPContractsManagerV2._assertValidFullConfig.
		expectedOrder := []embedded.GameType{
			embedded.GameTypeCannon,
			embedded.GameTypePermissionedCannon,
			embedded.GameTypeCannonKona,
			embedded.GameTypeSuperPermCannon,
			embedded.GameTypeSuperCannonKona,
			embedded.GameTypeZKDisputeGame,
		}
		require.Len(t, cfgs, len(expectedOrder))
		for i, want := range expectedOrder {
			require.Equal(t, want, cfgs[i].GameType, "game type at index %d", i)
		}

		// Only the ZK game (last entry) is enabled; all others are disabled with zero bond and no
		// sub-config.
		for i := 0; i < len(cfgs)-1; i++ {
			require.False(t, cfgs[i].Enabled, "config %d should be disabled", i)
			require.Equal(t, 0, cfgs[i].InitBond.Sign(), "disabled config %d should have zero bond", i)
			require.Nil(t, cfgs[i].ZKDisputeGameConfig)
			require.Nil(t, cfgs[i].FaultDisputeGameConfig)
			require.Nil(t, cfgs[i].PermissionedDisputeGameConfig)
			require.Nil(t, cfgs[i].SuperPermissionedDisputeGameConfig)
		}

		zk := cfgs[len(cfgs)-1]
		require.True(t, zk.Enabled)
		require.Equal(t, embedded.GameTypeZKDisputeGame, zk.GameType)
		require.Equal(t, p.InitBond, zk.InitBond)
		require.NotNil(t, zk.ZKDisputeGameConfig)
		require.Equal(t, p.AbsolutePrestate, zk.ZKDisputeGameConfig.AbsolutePrestate)
		require.Equal(t, p.Verifier, zk.ZKDisputeGameConfig.Verifier)
		require.Equal(t, p.MaxChallengeDuration, zk.ZKDisputeGameConfig.MaxChallengeDuration)
		require.Equal(t, p.MaxProveDuration, zk.ZKDisputeGameConfig.MaxProveDuration)
		require.Equal(t, p.InitBond, zk.ZKDisputeGameConfig.ChallengerBond)
	})

	t.Run("emits both override instructions with correctly encoded data", func(t *testing.T) {
		p := validZKSingleParams()
		in, err := buildMigrateToZKSingleInput(p)
		require.NoError(t, err)

		instrs := in.UpgradeInputV2.ExtraInstructions
		require.Len(t, instrs, 2)

		require.Equal(t, "overrides.cfg.startingRespectedGameType", instrs[0].Key)
		// abi.encode(uint32) is a single left-padded 32-byte word.
		require.Len(t, instrs[0].Data, 32)
		require.Equal(t, uint64(gameTypeZKDisputeGame), new(big.Int).SetBytes(instrs[0].Data).Uint64())

		require.Equal(t, "overrides.cfg.startingAnchorRoot", instrs[1].Key)
		// abi.encode(Proposal{bytes32,uint256}) is a static 64-byte tuple: root || l2SequenceNumber.
		require.Len(t, instrs[1].Data, 64)
		require.Equal(t, p.StartingAnchorRoot, common.BytesToHash(instrs[1].Data[0:32]))
		require.Equal(t, p.StartingAnchorL2Seq, new(big.Int).SetBytes(instrs[1].Data[32:64]).Uint64())
	})

	t.Run("rejects missing required inputs", func(t *testing.T) {
		cases := []struct {
			name   string
			mutate func(*migrateToZKSingleParams)
			errSub string
		}{
			{"zero prank", func(p *migrateToZKSingleParams) { p.Prank = common.Address{} }, "proxy admin owner"},
			{"zero opcm", func(p *migrateToZKSingleParams) { p.Opcm = common.Address{} }, "opcm"},
			{"zero system config", func(p *migrateToZKSingleParams) { p.SystemConfig = common.Address{} }, "system config"},
			{"nil bond", func(p *migrateToZKSingleParams) { p.InitBond = nil }, "initial bond"},
			{"zero bond", func(p *migrateToZKSingleParams) { p.InitBond = big.NewInt(0) }, "initial bond"},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				p := validZKSingleParams()
				tc.mutate(&p)
				_, err := buildMigrateToZKSingleInput(p)
				require.ErrorContains(t, err, tc.errSub)
			})
		}
	})
}

// TestMigrateToZKSingleInputEncodes exercises the real encode path the command runs
// (buildMigrateToZKSingleInput -> embedded.UpgradeOPChainInput.EncodedUpgradeInputV2), which mirrors
// the on-chain ABI shape and the ZK-config validation that OPContractsManagerUtils enforces. This is
// the analog of set_interop_dispute_games_test.go's TestEncodeZKGameArgs, adapted to the
// upgrade()-based path.
func TestMigrateToZKSingleInputEncodes(t *testing.T) {
	t.Run("valid input encodes", func(t *testing.T) {
		in, err := buildMigrateToZKSingleInput(validZKSingleParams())
		require.NoError(t, err)

		encoded, err := in.EncodedUpgradeInputV2()
		require.NoError(t, err)
		require.NotEmpty(t, encoded)
	})

	// ZK-field validation is delegated to embedded.EncodedUpgradeInputV2 rather than duplicated in
	// the builder, so these zero-value cases build fine but must fail at encode time.
	t.Run("encode rejects invalid ZK config", func(t *testing.T) {
		cases := []struct {
			name   string
			mutate func(*migrateToZKSingleParams)
			errSub string
		}{
			{"zero verifier", func(p *migrateToZKSingleParams) { p.Verifier = common.Address{} }, "Verifier"},
			{"zero prestate", func(p *migrateToZKSingleParams) { p.AbsolutePrestate = common.Hash{} }, "AbsolutePrestate"},
			{"zero max challenge duration", func(p *migrateToZKSingleParams) { p.MaxChallengeDuration = 0 }, "MaxChallengeDuration"},
			{"zero max prove duration", func(p *migrateToZKSingleParams) { p.MaxProveDuration = 0 }, "MaxProveDuration"},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				p := validZKSingleParams()
				tc.mutate(&p)
				in, err := buildMigrateToZKSingleInput(p)
				require.NoError(t, err, "builder delegates ZK validation to the encoder")
				_, err = in.EncodedUpgradeInputV2()
				require.ErrorContains(t, err, tc.errSub)
			})
		}
	})
}

// TestMigrateToZKSingle is a forked-Sepolia end-to-end test of the full
// Go -> forge script -> OPCMv2.upgrade() path. It deploys an isolated chain with the ZK and
// super-root-migration dev features enabled (so the OPCM ships a ZKDisputeGame impl and permits the
// startingAnchorRoot override), then migrates it to the ZK dispute game. UpgradeOPChain is a void
// script (no on-chain checkOutput), so a non-erroring run plus a single broadcast to the prank
// address proves the upgrade executed.
func TestMigrateToZKSingle(t *testing.T) {
	lgr := testlog.Logger(t, slog.LevelDebug)

	forkedL1, stopL1, err := devnet.NewForkedSepolia(lgr)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, stopL1())
	})
	l1RPC := forkedL1.RPCUrl()

	loc, afactsFS := testutil.LocalArtifacts(t)
	testCacheDir := testutils.IsolatedTestDirWithAutoCleanup(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	_, pk, dk := shared.DefaultPrivkey(t)

	l1ChainID := big.NewInt(11155111) // Sepolia
	l2ChainID := uint256.NewInt(12345)

	intent, st := shared.NewIntent(t, l1ChainID, dk, l2ChainID, loc, loc, 30_000_000)

	// Enable ZK (so DeployImplementations ships the ZKDisputeGame impl into the OPCM container) and
	// SuperRootGamesMigration (so OPCMv2._isPermittedInstruction permits the startingAnchorRoot
	// override). Interop is enabled to match the super-capable chain configuration.
	devBitmap := devfeatures.EnableDevFeature(common.Hash{}, devfeatures.OptimismPortalInteropFlag)
	devBitmap = devfeatures.EnableDevFeature(devBitmap, devfeatures.ZKDisputeGameFlag)
	devBitmap = devfeatures.EnableDevFeature(devBitmap, devfeatures.SuperRootGamesMigrationFlag)
	intent.GlobalDeployOverrides = map[string]any{
		"devFeatureBitmap": devBitmap,
	}
	intent.UseInterop = true

	err = deployer.ApplyPipeline(ctx, deployer.ApplyPipelineOpts{
		DeploymentTarget:   deployer.DeploymentTargetLive,
		L1RPCUrl:           l1RPC,
		DeployerPrivateKey: pk,
		Intent:             intent,
		State:              st,
		Logger:             lgr,
		StateWriter:        pipeline.NoopStateWriter(),
		CacheDir:           testCacheDir,
	})
	require.NoError(t, err, "Failed to deploy chain")

	require.Len(t, st.Chains, 1, "Expected one chain to be deployed")
	systemConfigProxy := st.Chains[0].SystemConfigProxy
	l1ProxyAdminOwner := intent.Chains[0].Roles.L1ProxyAdminOwner

	require.NotEqual(t, common.Address{}, st.ImplementationsDeployment.OpcmV2Impl, "OPCM V2 address should be set")
	opcmAddr := st.ImplementationsDeployment.OpcmV2Impl

	rpcClient, err := rpc.Dial(l1RPC)
	require.NoError(t, err)

	shared.DeployDummyCaller(t, rpcClient, afactsFS, l1ProxyAdminOwner, opcmAddr)

	bcast := new(broadcaster.CalldataBroadcaster)
	host, err := env.DefaultForkedScriptHost(ctx, bcast, lgr, l1ProxyAdminOwner, afactsFS, rpcClient)
	require.NoError(t, err)

	// Build the single-chain ZK migration input and run OPCMv2.upgrade().
	input, err := buildMigrateToZKSingleInput(migrateToZKSingleParams{
		Prank:                l1ProxyAdminOwner,
		Opcm:                 opcmAddr,
		SystemConfig:         systemConfigProxy,
		AbsolutePrestate:     common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000abc"),
		Verifier:             common.HexToAddress("0x000000000000000000000000000000000000bEEF"),
		MaxChallengeDuration: 7 * 24 * 60 * 60,
		MaxProveDuration:     3 * 24 * 60 * 60,
		InitBond:             big.NewInt(1000000000000000000),
		StartingAnchorRoot:   common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000def"),
		StartingAnchorL2Seq:  1,
	})
	require.NoError(t, err)

	require.NoError(t, MigrateToZKSingle(host, input), "ZK single-chain migration failed")

	dump, err := bcast.Dump()
	require.NoError(t, err)
	require.Len(t, dump, 1, "should have one transaction (the upgrade)")
	require.Equal(t, l1ProxyAdminOwner, *dump[0].To, "upgrade tx should be sent to the prank address")
}
