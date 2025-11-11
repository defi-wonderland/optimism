package pipeline

import (
	"fmt"
	"math/big"

	"github.com/ethereum-optimism/optimism/op-chain-ops/genesis"
	"github.com/ethereum/go-ethereum/common/hexutil"

	"github.com/ethereum-optimism/optimism/op-service/jsonutil"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/env"

	"github.com/ethereum-optimism/optimism/op-chain-ops/foundry"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/broadcaster"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/opcm"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/state"

	"github.com/ethereum/go-ethereum/common"
)

type l2GenesisOverrides struct {
	// ===== CUSTOM GAS TOKEN (CGT) CONFIGURATION =====
	UseCustomGasToken          bool           `json:"useCustomGasToken"`          // CGT: Enable custom gas token mode
	GasPayingTokenName         string         `json:"gasPayingTokenName"`         // CGT: Name of the custom gas token
	GasPayingTokenSymbol       string         `json:"gasPayingTokenSymbol"`       // CGT: Symbol of the custom gas token
	NativeAssetLiquidityAmount *hexutil.Big   `json:"nativeAssetLiquidityAmount"` // CGT: Liquidity amount for NativeAssetLiquidity contract
	LiquidityControllerOwner   common.Address `json:"liquidityControllerOwner"`   // CGT: Owner of the LiquidityController contract

	// ===== GENERAL L2 CONFIGURATION (NON-CGT) =====
	FundDevAccounts                          bool                      `json:"fundDevAccounts"`
	BaseFeeVaultMinimumWithdrawalAmount      *hexutil.Big              `json:"baseFeeVaultMinimumWithdrawalAmount"`
	L1FeeVaultMinimumWithdrawalAmount        *hexutil.Big              `json:"l1FeeVaultMinimumWithdrawalAmount"`
	SequencerFeeVaultMinimumWithdrawalAmount *hexutil.Big              `json:"sequencerFeeVaultMinimumWithdrawalAmount"`
	OperatorFeeVaultMinimumWithdrawalAmount  *hexutil.Big              `json:"operatorFeeVaultMinimumWithdrawalAmount"`
	BaseFeeVaultWithdrawalNetwork            genesis.WithdrawalNetwork `json:"baseFeeVaultWithdrawalNetwork"`
	L1FeeVaultWithdrawalNetwork              genesis.WithdrawalNetwork `json:"l1FeeVaultWithdrawalNetwork"`
	SequencerFeeVaultWithdrawalNetwork       genesis.WithdrawalNetwork `json:"sequencerFeeVaultWithdrawalNetwork"`
	OperatorFeeVaultWithdrawalNetwork        genesis.WithdrawalNetwork `json:"operatorFeeVaultWithdrawalNetwork"`
	EnableGovernance                         bool                      `json:"enableGovernance"`
	GovernanceTokenOwner                     common.Address            `json:"governanceTokenOwner"`
}

func GenerateL2Genesis(pEnv *Env, intent *state.Intent, bundle ArtifactsBundle, st *state.State, chainID common.Hash) error {
	lgr := pEnv.Logger.New("stage", "generate-l2-genesis")

	thisIntent, err := intent.Chain(chainID)
	if err != nil {
		return fmt.Errorf("failed to get chain intent: %w", err)
	}

	thisChainState, err := st.Chain(chainID)
	if err != nil {
		return fmt.Errorf("failed to get chain state: %w", err)
	}

	if !shouldGenerateL2Genesis(thisChainState) {
		lgr.Info("L2 genesis generation not needed")
		return nil
	}

	lgr.Info("generating L2 genesis", "id", chainID.Hex())

	host, err := env.DefaultScriptHost(
		broadcaster.NoopBroadcaster(),
		pEnv.Logger,
		pEnv.Deployer,
		bundle.L2,
	)
	if err != nil {
		return fmt.Errorf("failed to create L2 script host: %w", err)
	}

	script, err := opcm.NewL2GenesisScript(host)
	if err != nil {
		return fmt.Errorf("failed to create L2Genesis script: %w", err)
	}

	overrides, schedule, err := calculateL2GenesisOverrides(intent, thisIntent)
	if err != nil {
		return fmt.Errorf("failed to calculate L2 genesis overrides: %w", err)
	}

	// Resolve effective CGT configuration without mutating the intent
	effectiveCGT := resolveEffectiveCGT(thisIntent, overrides)

	if err := script.Run(opcm.L2GenesisInput{
		L1ChainID:                                new(big.Int).SetUint64(intent.L1ChainID),
		L2ChainID:                                chainID.Big(),
		L1CrossDomainMessengerProxy:              thisChainState.L1CrossDomainMessengerProxy,
		L1StandardBridgeProxy:                    thisChainState.L1StandardBridgeProxy,
		L1ERC721BridgeProxy:                      thisChainState.L1Erc721BridgeProxy,
		OpChainProxyAdminOwner:                   thisIntent.Roles.L2ProxyAdminOwner,
		BaseFeeVaultWithdrawalNetwork:            wdNetworkToBig(overrides.BaseFeeVaultWithdrawalNetwork),
		L1FeeVaultWithdrawalNetwork:              wdNetworkToBig(overrides.L1FeeVaultWithdrawalNetwork),
		SequencerFeeVaultWithdrawalNetwork:       wdNetworkToBig(overrides.SequencerFeeVaultWithdrawalNetwork),
		OperatorFeeVaultWithdrawalNetwork:        wdNetworkToBig(overrides.OperatorFeeVaultWithdrawalNetwork),
		SequencerFeeVaultMinimumWithdrawalAmount: overrides.SequencerFeeVaultMinimumWithdrawalAmount.ToInt(),
		BaseFeeVaultMinimumWithdrawalAmount:      overrides.BaseFeeVaultMinimumWithdrawalAmount.ToInt(),
		L1FeeVaultMinimumWithdrawalAmount:        overrides.L1FeeVaultMinimumWithdrawalAmount.ToInt(),
		OperatorFeeVaultMinimumWithdrawalAmount:  overrides.OperatorFeeVaultMinimumWithdrawalAmount.ToInt(),
		BaseFeeVaultRecipient:                    thisIntent.BaseFeeVaultRecipient,
		L1FeeVaultRecipient:                      thisIntent.L1FeeVaultRecipient,
		SequencerFeeVaultRecipient:               thisIntent.SequencerFeeVaultRecipient,
		OperatorFeeVaultRecipient:                thisIntent.OperatorFeeVaultRecipient,
		GovernanceTokenOwner:                     overrides.GovernanceTokenOwner,
		Fork:                                     big.NewInt(schedule.SolidityForkNumber(1)),
		DeployCrossL2Inbox:                       len(intent.Chains) > 1,
		EnableGovernance:                         overrides.EnableGovernance,
		FundDevAccounts:                          overrides.FundDevAccounts,
		UseRevenueShare:                          thisIntent.UseRevenueShare,
		ChainFeesRecipient:                       thisIntent.ChainFeesRecipient,
		L1FeesDepositor:                          standard.L1FeesDepositor,
		// Custom Gas Token (CGT) configuration passed to L2Genesis script
		UseCustomGasToken:          effectiveCGT.UseCustomGasToken,          // CGT: Enable/disable custom gas token (inferred from Name/Symbol)
		GasPayingTokenName:         effectiveCGT.GasPayingTokenName,         // CGT: Token name (e.g., "Custom Gas Token")
		GasPayingTokenSymbol:       effectiveCGT.GasPayingTokenSymbol,       // CGT: Token symbol (e.g., "CGT")
		NativeAssetLiquidityAmount: effectiveCGT.NativeAssetLiquidityAmount, // CGT: Liquidity amount (defaults to type(uint248).max)
		LiquidityControllerOwner:   effectiveCGT.LiquidityControllerOwner,   // CGT: LiquidityController owner (defaults to L2ProxyAdminOwner)
	}); err != nil {
		return fmt.Errorf("failed to call L2Genesis script: %w", err)
	}

	host.Wipe(pEnv.Deployer)

	dump, err := host.StateDump()
	if err != nil {
		return fmt.Errorf("failed to dump state: %w", err)
	}

	thisChainState.Allocs = &state.GzipData[foundry.ForgeAllocs]{
		Data: dump,
	}

	return nil
}

func calculateL2GenesisOverrides(intent *state.Intent, thisIntent *state.ChainIntent) (l2GenesisOverrides, *genesis.UpgradeScheduleDeployConfig, error) {
	schedule := standard.DefaultHardforkScheduleForTag(standard.CurrentTag)

	overrides := defaultOverrides()
	// Special case for FundDevAccounts since it's both an intent value and an override.
	overrides.FundDevAccounts = intent.FundDevAccounts

	var err error
	if len(intent.GlobalDeployOverrides) > 0 {
		schedule, err = jsonutil.MergeJSON(schedule, intent.GlobalDeployOverrides)
		if err != nil {
			return l2GenesisOverrides{}, nil, fmt.Errorf("failed to merge global deploy overrides: %w", err)
		}
		overrides, err = jsonutil.MergeJSON(overrides, intent.GlobalDeployOverrides)
		if err != nil {
			return l2GenesisOverrides{}, nil, fmt.Errorf("failed to merge global deploy overrides: %w", err)
		}
	}

	if len(thisIntent.DeployOverrides) > 0 {
		schedule, err = jsonutil.MergeJSON(schedule, thisIntent.DeployOverrides)
		if err != nil {
			return l2GenesisOverrides{}, nil, fmt.Errorf("failed to merge L2 deploy overrides: %w", err)
		}
		overrides, err = jsonutil.MergeJSON(overrides, thisIntent.DeployOverrides)
		if err != nil {
			return l2GenesisOverrides{}, nil, fmt.Errorf("failed to merge global deploy overrides: %w", err)
		}
	}

	// Validate that standard chains don't enable custom gas token
	if intent.ConfigType == state.IntentTypeStandard {
		// Check both intent and override configurations
		intentHasCGT := thisIntent.IsCustomGasTokenEnabled()
		overrideHasCGT := overrides.UseCustomGasToken
		if intentHasCGT || overrideHasCGT {
			return l2GenesisOverrides{}, nil, fmt.Errorf(
				"custom gas token cannot be enabled on standard chain (chainId=%s). "+
					"Standard chains must use ETH as the native gas token. "+
					"To use a custom gas token, the intent must be created with configType=\"custom\" or \"standard-overrides\"",
				thisIntent.ID)
		}
	}

	return overrides, schedule, nil
}

func shouldGenerateL2Genesis(thisChainState *state.ChainState) bool {
	return thisChainState.Allocs == nil
}

// effectiveCGTConfig represents the resolved CGT configuration to pass to L2Genesis script.
type effectiveCGTConfig struct {
	UseCustomGasToken          bool
	GasPayingTokenName         string
	GasPayingTokenSymbol       string
	NativeAssetLiquidityAmount *big.Int
	LiquidityControllerOwner   common.Address
}

// resolveEffectiveCGT computes the effective CGT configuration without mutating the input intent.
// It prioritizes the intent configuration, but falls back to overrides if the intent doesn't have CGT enabled.
func resolveEffectiveCGT(thisIntent *state.ChainIntent, overrides l2GenesisOverrides) effectiveCGTConfig {
	// If intent has CGT enabled, use intent values
	if thisIntent.IsCustomGasTokenEnabled() {
		return effectiveCGTConfig{
			UseCustomGasToken:          true,
			GasPayingTokenName:         thisIntent.CustomGasToken.Name,
			GasPayingTokenSymbol:       thisIntent.CustomGasToken.Symbol,
			NativeAssetLiquidityAmount: thisIntent.GetInitialLiquidity(),
			LiquidityControllerOwner:   thisIntent.GetLiquidityControllerOwner(),
		}
	}

	// If intent doesn't have CGT enabled but overrides do, use override values
	if overrides.UseCustomGasToken {
		var liquidity *big.Int

		// Check if liquidity is set in overrides
		if overrides.NativeAssetLiquidityAmount != nil {
			liquidity = overrides.NativeAssetLiquidityAmount.ToInt()
		}

		// If liquidity is not set (nil or 0), use type(uint248).max as default
		if liquidity == nil || liquidity.Sign() == 0 {
			maxUint248 := new(big.Int)
			maxUint248.SetString("00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
			liquidity = maxUint248
		}

		// Use override value if set, otherwise fall back to L2ProxyAdminOwner
		owner := overrides.LiquidityControllerOwner
		if owner == (common.Address{}) {
			owner = thisIntent.Roles.L2ProxyAdminOwner
		}

		return effectiveCGTConfig{
			UseCustomGasToken:          true,
			GasPayingTokenName:         overrides.GasPayingTokenName,
			GasPayingTokenSymbol:       overrides.GasPayingTokenSymbol,
			NativeAssetLiquidityAmount: liquidity,
			LiquidityControllerOwner:   owner,
		}
	}

	// CGT not enabled in either intent or overrides
	return effectiveCGTConfig{
		UseCustomGasToken:          false,
		GasPayingTokenName:         "",
		GasPayingTokenSymbol:       "",
		NativeAssetLiquidityAmount: big.NewInt(0),
		LiquidityControllerOwner:   common.Address{},
	}
}

func wdNetworkToBig(wd genesis.WithdrawalNetwork) *big.Int {
	n := wd.ToUint8()
	return big.NewInt(int64(n))
}

func defaultOverrides() l2GenesisOverrides {
	return l2GenesisOverrides{
		// ===== GENERAL L2 DEFAULTS =====
		FundDevAccounts:                          false,
		BaseFeeVaultMinimumWithdrawalAmount:      standard.VaultMinWithdrawalAmount,
		L1FeeVaultMinimumWithdrawalAmount:        standard.VaultMinWithdrawalAmount,
		SequencerFeeVaultMinimumWithdrawalAmount: standard.VaultMinWithdrawalAmount,
		OperatorFeeVaultMinimumWithdrawalAmount:  standard.VaultMinWithdrawalAmount,
		BaseFeeVaultWithdrawalNetwork:            "local",
		L1FeeVaultWithdrawalNetwork:              "local",
		SequencerFeeVaultWithdrawalNetwork:       "local",
		OperatorFeeVaultWithdrawalNetwork:        "local",
		EnableGovernance:                         false,
		GovernanceTokenOwner:                     standard.GovernanceTokenOwner,
		// ===== CGT DEFAULTS =====
		UseCustomGasToken:          false,           // CGT disabled by default
		GasPayingTokenName:         "",              // Empty when CGT disabled
		GasPayingTokenSymbol:       "",              // Empty when CGT disabled
		NativeAssetLiquidityAmount: nil,             // nil triggers type(uint248).max fallback when CGT enabled
		LiquidityControllerOwner:   common.Address{}, // Empty address triggers L2ProxyAdminOwner fallback when CGT enabled
	}
}
