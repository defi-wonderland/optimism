package manage

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum-optimism/optimism/op-chain-ops/script"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/upgrade/embedded"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/env"
	opcrypto "github.com/ethereum-optimism/optimism/op-service/crypto"
	"github.com/ethereum-optimism/optimism/op-service/ioutil"
	oplog "github.com/ethereum-optimism/optimism/op-service/log"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
	"github.com/urfave/cli/v2"
)

// migrateToZKSingleParams holds the parsed inputs required to build a single-chain migration to the
// ZK dispute game. It is kept separate from the cli.Context so the input-building logic can be
// exercised in unit tests without a live chain.
type migrateToZKSingleParams struct {
	Prank                common.Address
	Opcm                 common.Address
	SystemConfig         common.Address
	AbsolutePrestate     common.Hash
	Verifier             common.Address
	MaxChallengeDuration uint64
	MaxProveDuration     uint64
	InitBond             *big.Int
	StartingAnchorRoot   common.Hash
	StartingAnchorL2Seq  uint64
}

// buildMigrateToZKSingleInput assembles the OPCMv2.upgrade() input that migrates an isolated chain
// from its current super game (SuperFaultDisputeGame or SuperPermissionedDisputeGame) to the ZK
// dispute game. Every existing game type is disabled and only ZK_DISPUTE_GAME is enabled, and the
// respected game type is flipped to ZK. The starting anchor root is always overridden so the
// re-initialized AnchorStateRegistry seeds the ZK game from the supplied honest anchor.
//
// Detailed ZK-config validation (non-zero verifier/prestate, positive durations/bond) is delegated
// to embedded.EncodedUpgradeInputV2 at run time; this function only validates the top-level inputs
// it owns.
func buildMigrateToZKSingleInput(p migrateToZKSingleParams) (embedded.UpgradeOPChainInput, error) {
	var zero embedded.UpgradeOPChainInput

	if p.Prank == (common.Address{}) {
		return zero, fmt.Errorf("l1 proxy admin owner must not be the zero address")
	}
	if p.Opcm == (common.Address{}) {
		return zero, fmt.Errorf("opcm must not be the zero address")
	}
	if p.SystemConfig == (common.Address{}) {
		return zero, fmt.Errorf("system config proxy must not be the zero address")
	}
	if p.InitBond == nil || p.InitBond.Sign() <= 0 {
		// The ZK game is enabled, so _assertValidFullConfig requires a non-zero init bond.
		return zero, fmt.Errorf("initial bond must be a positive value")
	}

	// Build the full, ordered game-config array. The order MUST match the validGameTypes array in
	// OPContractsManagerV2._assertValidFullConfig: CANNON, PERMISSIONED_CANNON, CANNON_KONA,
	// SUPER_PERMISSIONED_CANNON, SUPER_CANNON_KONA, ZK_DISPUTE_GAME. All are disabled except ZK.
	disputeGameConfigs := buildZKSingleDisputeGameConfigs(&embedded.ZKDisputeGameConfig{
		AbsolutePrestate:     p.AbsolutePrestate,
		Verifier:             p.Verifier,
		MaxChallengeDuration: p.MaxChallengeDuration,
		MaxProveDuration:     p.MaxProveDuration,
		ChallengerBond:       p.InitBond,
	}, p.InitBond)

	// Flip the respected game type to ZK. Required because the previously-respected super game is
	// being disabled by this upgrade; without the override, _loadFullConfig would load the old
	// respected type and _assertValidFullConfig would revert.
	respectedData, err := encodeStartingRespectedGameType(gameTypeZKDisputeGame)
	if err != nil {
		return zero, fmt.Errorf("failed to encode startingRespectedGameType override: %w", err)
	}

	// Seed the re-initialized AnchorStateRegistry from the supplied honest anchor. Gated on the
	// SUPER_ROOT_GAMES_MIGRATION dev feature in OPContractsManagerV2._isPermittedInstruction.
	anchorData, err := encodeStartingAnchorRoot(p.StartingAnchorRoot, p.StartingAnchorL2Seq)
	if err != nil {
		return zero, fmt.Errorf("failed to encode startingAnchorRoot override: %w", err)
	}

	return embedded.UpgradeOPChainInput{
		Prank: p.Prank,
		Opcm:  p.Opcm,
		UpgradeInputV2: &embedded.UpgradeInputV2{
			SystemConfig:       p.SystemConfig,
			DisputeGameConfigs: disputeGameConfigs,
			ExtraInstructions: []embedded.ExtraInstruction{
				{Key: "overrides.cfg.startingRespectedGameType", Data: respectedData},
				{Key: "overrides.cfg.startingAnchorRoot", Data: anchorData},
			},
		},
	}, nil
}

// buildZKSingleDisputeGameConfigs returns the full game-config array with every game type disabled
// except the ZK dispute game. The slice order is significant and must match the validGameTypes
// array in OPContractsManagerV2._assertValidFullConfig.
func buildZKSingleDisputeGameConfigs(
	zkCfg *embedded.ZKDisputeGameConfig,
	initBond *big.Int,
) []embedded.DisputeGameConfig {
	return []embedded.DisputeGameConfig{
		{Enabled: false, InitBond: new(big.Int), GameType: embedded.GameTypeCannon},
		{Enabled: false, InitBond: new(big.Int), GameType: embedded.GameTypePermissionedCannon},
		{Enabled: false, InitBond: new(big.Int), GameType: embedded.GameTypeCannonKona},
		{Enabled: false, InitBond: new(big.Int), GameType: embedded.GameTypeSuperPermCannon},
		{Enabled: false, InitBond: new(big.Int), GameType: embedded.GameTypeSuperCannonKona},
		{
			Enabled:             true,
			InitBond:            initBond,
			GameType:            embedded.GameTypeZKDisputeGame,
			ZKDisputeGameConfig: zkCfg,
		},
	}
}

// encodeStartingRespectedGameType ABI-encodes a GameType (uint32) for the
// "overrides.cfg.startingRespectedGameType" upgrade instruction. OPCM decodes this via
// abi.decode(data, (GameType)).
func encodeStartingRespectedGameType(gameType uint32) ([]byte, error) {
	uint32Ty, err := abi.NewType("uint32", "", nil)
	if err != nil {
		return nil, err
	}
	return abi.Arguments{{Type: uint32Ty}}.Pack(gameType)
}

// encodeStartingAnchorRoot ABI-encodes a Proposal{bytes32 root, uint256 l2SequenceNumber} for the
// "overrides.cfg.startingAnchorRoot" upgrade instruction. OPCM decodes this via
// abi.decode(data, (Proposal)).
func encodeStartingAnchorRoot(root common.Hash, l2SequenceNumber uint64) ([]byte, error) {
	proposalTy, err := abi.NewType("tuple", "", []abi.ArgumentMarshaling{
		{Name: "root", Type: "bytes32"},
		{Name: "l2SequenceNumber", Type: "uint256"},
	})
	if err != nil {
		return nil, err
	}
	return abi.Arguments{{Type: proposalTy}}.Pack(struct {
		Root             common.Hash
		L2SequenceNumber *big.Int
	}{
		Root:             root,
		L2SequenceNumber: new(big.Int).SetUint64(l2SequenceNumber),
	})
}

// MigrateToZKSingle runs the UpgradeOPChain forge script (OPCMv2.upgrade) for an isolated chain,
// swapping its super game for the ZK dispute game. It reuses the embedded upgrade primitives, which
// validate and encode the ZK config and run the script against the supplied forked host.
func MigrateToZKSingle(host *script.Host, input embedded.UpgradeOPChainInput) error {
	return embedded.Upgrade(host, input)
}

// migrateToZKSingleOutput is a small JSON summary emitted after a successful migration.
type migrateToZKSingleOutput struct {
	SystemConfig      common.Address `json:"systemConfig"`
	RespectedGameType uint32         `json:"respectedGameType"`
}

// MigrateToZKSingleCLI is the entry point for the `manage migrate-to-zk-single` command. It builds
// the OPCMv2.upgrade input that migrates an isolated chain from its current super game (SFDG/SPDG)
// to the ZK dispute game and runs the upgrade against a forked L1.
func MigrateToZKSingleCLI(cliCtx *cli.Context) error {
	logCfg := oplog.ReadCLIConfig(cliCtx)
	lgr := oplog.NewLogger(oplog.AppOut(cliCtx), logCfg)
	oplog.SetGlobalLogHandler(lgr.Handler())

	ctx, cancel := context.WithCancel(cliCtx.Context)
	defer cancel()

	l1RPCUrl := cliCtx.String(deployer.L1RPCURLFlag.Name)
	if l1RPCUrl == "" {
		return fmt.Errorf("missing required flag: %s", deployer.L1RPCURLFlag.Name)
	}

	privateKey := cliCtx.String(deployer.PrivateKeyFlag.Name)
	if privateKey == "" {
		return fmt.Errorf("missing required flag: %s", deployer.PrivateKeyFlag.Name)
	}
	privateKeyECDSA, err := crypto.HexToECDSA(strings.TrimPrefix(privateKey, "0x"))
	if err != nil {
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	opcmFlag := cliCtx.String(OPCMImplFlag.Name)
	if opcmFlag == "" {
		return fmt.Errorf("missing required flag: %s", OPCMImplFlag.Name)
	}

	l1ProxyAdminOwnerFlag := cliCtx.String(L1ProxyAdminOwnerFlag.Name)
	if l1ProxyAdminOwnerFlag == "" {
		return fmt.Errorf("missing required flag: %s", L1ProxyAdminOwnerFlag.Name)
	}

	systemConfigFlag := cliCtx.String(SystemConfigProxyFlag.Name)
	if systemConfigFlag == "" {
		return fmt.Errorf("missing required flag: %s", SystemConfigProxyFlag.Name)
	}

	startingAnchorRootFlag := cliCtx.String(StartingAnchorRootFlag.Name)
	if startingAnchorRootFlag == "" {
		return fmt.Errorf("missing required flag: %s", StartingAnchorRootFlag.Name)
	}

	verifierFlag := cliCtx.String(ZKVerifierFlag.Name)
	if verifierFlag == "" {
		return fmt.Errorf("missing required flag: %s", ZKVerifierFlag.Name)
	}

	initBondStr := cliCtx.String(InitialBondFlag.Name)
	if initBondStr == "" {
		return fmt.Errorf("missing required flag: %s", InitialBondFlag.Name)
	}
	initBond, ok := new(big.Int).SetString(initBondStr, 10)
	if !ok {
		return fmt.Errorf("failed to parse initial bond: %s", initBondStr)
	}

	input, err := buildMigrateToZKSingleInput(migrateToZKSingleParams{
		Prank:                common.HexToAddress(l1ProxyAdminOwnerFlag),
		Opcm:                 common.HexToAddress(opcmFlag),
		SystemConfig:         common.HexToAddress(systemConfigFlag),
		AbsolutePrestate:     common.HexToHash(cliCtx.String(DisputeAbsolutePrestateFlag.Name)),
		Verifier:             common.HexToAddress(verifierFlag),
		MaxChallengeDuration: cliCtx.Uint64(ZKMaxChallengeDurationFlag.Name),
		MaxProveDuration:     cliCtx.Uint64(ZKMaxProveDurationFlag.Name),
		InitBond:             initBond,
		StartingAnchorRoot:   common.HexToHash(startingAnchorRootFlag),
		StartingAnchorL2Seq:  cliCtx.Uint64(StartingAnchorL2SequenceNumberFlag.Name),
	})
	if err != nil {
		return err
	}

	artifactsLocatorStr := cliCtx.String(deployer.ArtifactsLocatorFlag.Name)
	artifactsLocator := new(artifacts.Locator)
	if err := artifactsLocator.UnmarshalText([]byte(artifactsLocatorStr)); err != nil {
		return fmt.Errorf("failed to parse artifacts locator: %w", err)
	}

	l1RPC, err := rpc.Dial(l1RPCUrl)
	if err != nil {
		return fmt.Errorf("failed to dial RPC %s: %w", l1RPCUrl, err)
	}

	cacheDir := cliCtx.String(deployer.CacheDirFlag.Name)
	artifactsFS, err := artifacts.Download(ctx, artifactsLocator, ioutil.BarProgressor(), cacheDir)
	if err != nil {
		return fmt.Errorf("failed to download artifacts: %w", err)
	}

	l1Client := ethclient.NewClient(l1RPC)
	defer l1Client.Close()

	l1ChainID, err := l1Client.ChainID(ctx)
	if err != nil {
		return fmt.Errorf("failed to get chain ID: %w", err)
	}

	signer := opcrypto.SignerFnFromBind(opcrypto.PrivateKeySignerFn(privateKeyECDSA, l1ChainID))
	deployerAddr := crypto.PubkeyToAddress(privateKeyECDSA.PublicKey)
	bcaster, err := broadcaster.NewKeyedBroadcaster(broadcaster.KeyedBroadcasterOpts{
		Logger:  lgr,
		ChainID: l1ChainID,
		Client:  l1Client,
		Signer:  signer,
		From:    deployerAddr,
	})
	if err != nil {
		return fmt.Errorf("failed to create broadcaster: %w", err)
	}

	l1Host, err := env.DefaultForkedScriptHost(ctx, bcaster, lgr, deployerAddr, artifactsFS, l1RPC)
	if err != nil {
		return fmt.Errorf("failed to create script host: %w", err)
	}

	if err := MigrateToZKSingle(l1Host, input); err != nil {
		return fmt.Errorf("failed to run ZK single-chain migration: %w", err)
	}

	enc := json.NewEncoder(cliCtx.App.Writer)
	enc.SetIndent("", "  ")
	if err := enc.Encode(migrateToZKSingleOutput{
		SystemConfig:      input.UpgradeInputV2.SystemConfig,
		RespectedGameType: gameTypeZKDisputeGame,
	}); err != nil {
		return fmt.Errorf("failed to encode migration output: %w", err)
	}

	return nil
}
