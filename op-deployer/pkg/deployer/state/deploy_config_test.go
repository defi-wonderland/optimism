package state

import (
	"math/big"
	"testing"

	"github.com/ethereum-optimism/optimism/op-chain-ops/addresses"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/stretchr/testify/require"
)

func TestCombineDeployConfig(t *testing.T) {
	intent := Intent{
		L1ChainID:          1,
		L1ContractsLocator: artifacts.EmbeddedLocator,
	}
	chainState := ChainState{
		ID: common.HexToHash("0x123"),
	}
	chainIntent := ChainIntent{
		Eip1559Denominator:         1,
		Eip1559Elasticity:          2,
		GasLimit:                   standard.GasLimit,
		BaseFeeVaultRecipient:      common.HexToAddress("0x123"),
		L1FeeVaultRecipient:        common.HexToAddress("0x456"),
		SequencerFeeVaultRecipient: common.HexToAddress("0x789"),
		OperatorFeeVaultRecipient:  common.HexToAddress("0xabc"),
		Roles: ChainRoles{
			SystemConfigOwner: common.HexToAddress("0x123"),
			L1ProxyAdminOwner: common.HexToAddress("0x456"),
			L2ProxyAdminOwner: common.HexToAddress("0x789"),
			UnsafeBlockSigner: common.HexToAddress("0xabc"),
			Batcher:           common.HexToAddress("0xdef"),
		},
		UseRevenueShare:    true,
		ChainFeesRecipient: common.HexToAddress("0x123"),
		// CustomGasToken defaults to disabled (all fields nil/empty)
		CustomGasToken: CustomGasToken{},
	}
	state := State{
		SuperchainDeployment: &addresses.SuperchainContracts{ProtocolVersionsProxy: common.HexToAddress("0x123")},
	}

	// apply hard fork overrides
	chainIntent.DeployOverrides = map[string]any{
		"l2GenesisFjordTimeOffset":    "0x1",
		"l2GenesisGraniteTimeOffset":  "0x2",
		"l2GenesisHoloceneTimeOffset": "0x3",
		"l2GenesisIsthmusTimeOffset":  "0x4",
		"l2GenesisJovianTimeOffset":   "0x5",
		"l2GenesisInteropTimeOffset":  "0x6",
	}

	out, err := CombineDeployConfig(&intent, &chainIntent, &state, &chainState)
	require.NoError(t, err)
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisFjordTimeOffset, hexutil.Uint64(1))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisGraniteTimeOffset, hexutil.Uint64(2))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisHoloceneTimeOffset, hexutil.Uint64(3))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisIsthmusTimeOffset, hexutil.Uint64(4))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisJovianTimeOffset, hexutil.Uint64(5))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisInteropTimeOffset, hexutil.Uint64(6))
}

// TestCombineDeployConfig_CGTViaOverrides tests that when custom gas token is enabled via
// GlobalDeployOverrides (without specifying nativeAssetLiquidityAmount), the default value
// of type(uint248).max is correctly applied.
func TestCombineDeployConfig_CGTViaOverrides(t *testing.T) {
	intent := Intent{
		L1ChainID:          1,
		L1ContractsLocator: artifacts.EmbeddedLocator,
		// Enable CGT via GlobalDeployOverrides without specifying nativeAssetLiquidityAmount
		GlobalDeployOverrides: map[string]any{
			"useCustomGasToken":    true,
			"gasPayingTokenName":   "Custom Token",
			"gasPayingTokenSymbol": "CT",
		},
	}
	chainState := ChainState{
		ID: common.HexToHash("0x123"),
	}
	chainIntent := ChainIntent{
		Eip1559Denominator:         1,
		Eip1559Elasticity:          2,
		GasLimit:                   standard.GasLimit,
		BaseFeeVaultRecipient:      common.HexToAddress("0x123"),
		L1FeeVaultRecipient:        common.HexToAddress("0x456"),
		SequencerFeeVaultRecipient: common.HexToAddress("0x789"),
		OperatorFeeVaultRecipient:  common.HexToAddress("0xabc"),
		Roles: ChainRoles{
			SystemConfigOwner: common.HexToAddress("0x123"),
			L1ProxyAdminOwner: common.HexToAddress("0x456"),
			L2ProxyAdminOwner: common.HexToAddress("0x789"),
			UnsafeBlockSigner: common.HexToAddress("0xabc"),
			Batcher:           common.HexToAddress("0xdef"),
		},
		UseRevenueShare:    false,
		ChainFeesRecipient: common.Address{},
		// CGT not enabled in intent
		CustomGasToken: CustomGasToken{},
	}
	state := State{
		SuperchainDeployment: &addresses.SuperchainContracts{ProtocolVersionsProxy: common.HexToAddress("0x123")},
	}

	out, err := CombineDeployConfig(&intent, &chainIntent, &state, &chainState)
	require.NoError(t, err)

	// Verify CGT is enabled
	require.True(t, out.UseCustomGasToken, "CGT should be enabled via overrides")
	require.Equal(t, "Custom Token", out.GasPayingTokenName)
	require.Equal(t, "CT", out.GasPayingTokenSymbol)

	// Verify NativeAssetLiquidityAmount is set to type(uint248).max (the default)
	expectedMaxUint248 := new(big.Int)
	expectedMaxUint248.SetString("00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
	require.NotNil(t, out.NativeAssetLiquidityAmount, "NativeAssetLiquidityAmount should not be nil")
	require.Equal(t, expectedMaxUint248, out.NativeAssetLiquidityAmount.ToInt(), "NativeAssetLiquidityAmount should be type(uint248).max")

	// Verify LiquidityControllerOwner is set to L2ProxyAdminOwner (the default)
	require.Equal(t, chainIntent.Roles.L2ProxyAdminOwner, out.LiquidityControllerOwner, "LiquidityControllerOwner should default to L2ProxyAdminOwner")
}
