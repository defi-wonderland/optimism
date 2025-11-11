package pipeline

import (
	"math/big"
	"testing"

	"github.com/ethereum-optimism/optimism/op-chain-ops/genesis"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/state"
	op_service "github.com/ethereum-optimism/optimism/op-service"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"

	"github.com/stretchr/testify/require"
)

func TestCalculateL2GenesisOverrides(t *testing.T) {
	testCases := []struct {
		name              string
		intent            *state.Intent
		chainIntent       *state.ChainIntent
		expectError       bool
		expectedOverrides l2GenesisOverrides
		expectedSchedule  func() *genesis.UpgradeScheduleDeployConfig
	}{
		{
			name: "basic",
			intent: &state.Intent{
				L1ContractsLocator: &artifacts.Locator{},
			},
			chainIntent:       &state.ChainIntent{},
			expectError:       false,
			expectedOverrides: defaultOverrides(),
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				return standard.DefaultHardforkScheduleForTag("")
			},
		},
		{
			name: "special case for fund dev accounts in intent",
			intent: &state.Intent{
				L1ContractsLocator: &artifacts.Locator{},
				FundDevAccounts:    true,
			},
			chainIntent: &state.ChainIntent{},
			expectError: false,
			expectedOverrides: func() l2GenesisOverrides {
				defaults := defaultOverrides()
				defaults.FundDevAccounts = true
				return defaults
			}(),
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				return standard.DefaultHardforkScheduleForTag("")
			},
		},
		{
			name: "with overrides",
			intent: &state.Intent{
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"fundDevAccounts":                          true,
					"baseFeeVaultMinimumWithdrawalAmount":      "0x1234",
					"l1FeeVaultMinimumWithdrawalAmount":        "0x2345",
					"sequencerFeeVaultMinimumWithdrawalAmount": "0x3456",
					"operatorFeeVaultMinimumWithdrawalAmount":  "0x4567",
					"baseFeeVaultWithdrawalNetwork":            "remote",
					"l1FeeVaultWithdrawalNetwork":              "remote",
					"sequencerFeeVaultWithdrawalNetwork":       "remote",
					"operatorFeeVaultWithdrawalNetwork":        "remote",
					"enableGovernance":                         true,
					"governanceTokenOwner":                     "0x1111111111111111111111111111111111111111",
					"l2GenesisInteropTimeOffset":               "0x1234",
					"chainFeesRecipient":                       "0x0000000000000000000000000000000000005678",
					"useCustomGasToken":                        false,
					"gasPayingTokenName":                       "",
					"gasPayingTokenSymbol":                     "",
					"nativeAssetLiquidityAmount":               "0x0",
				},
			},
			chainIntent: &state.ChainIntent{},
			expectError: false,
			expectedOverrides: l2GenesisOverrides{
				FundDevAccounts:                          true,
				BaseFeeVaultMinimumWithdrawalAmount:      (*hexutil.Big)(hexutil.MustDecodeBig("0x1234")),
				L1FeeVaultMinimumWithdrawalAmount:        (*hexutil.Big)(hexutil.MustDecodeBig("0x2345")),
				SequencerFeeVaultMinimumWithdrawalAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x3456")),
				OperatorFeeVaultMinimumWithdrawalAmount:  (*hexutil.Big)(hexutil.MustDecodeBig("0x4567")),
				BaseFeeVaultWithdrawalNetwork:            "remote",
				L1FeeVaultWithdrawalNetwork:              "remote",
				SequencerFeeVaultWithdrawalNetwork:       "remote",
				OperatorFeeVaultWithdrawalNetwork:        "remote",
				EnableGovernance:                         true,
				GovernanceTokenOwner:                     common.HexToAddress("0x1111111111111111111111111111111111111111"),
				NativeAssetLiquidityAmount:               (*hexutil.Big)(hexutil.MustDecodeBig("0x0")),
			},
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				sched := standard.DefaultHardforkScheduleForTag("")
				sched.L2GenesisInteropTimeOffset = op_service.U64UtilPtr(0x1234)
				return sched
			},
		},
		{
			name: "with chain-specific overrides",
			intent: &state.Intent{
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"fundDevAccounts": false,
				},
			},
			chainIntent: &state.ChainIntent{
				DeployOverrides: map[string]any{
					"fundDevAccounts":                          true,
					"baseFeeVaultMinimumWithdrawalAmount":      "0x1234",
					"l1FeeVaultMinimumWithdrawalAmount":        "0x2345",
					"sequencerFeeVaultMinimumWithdrawalAmount": "0x3456",
					"baseFeeVaultWithdrawalNetwork":            "remote",
					"l1FeeVaultWithdrawalNetwork":              "remote",
					"sequencerFeeVaultWithdrawalNetwork":       "remote",
					"operatorFeeVaultWithdrawalNetwork":        "remote",
					"enableGovernance":                         true,
					"governanceTokenOwner":                     "0x1111111111111111111111111111111111111111",
					"l2GenesisInteropTimeOffset":               "0x1234",
					"useCustomGasToken":                        false,
					"gasPayingTokenName":                       "",
					"gasPayingTokenSymbol":                     "",
					"nativeAssetLiquidityAmount":               "0x0",
				},
			},
			expectError: false,
			expectedOverrides: l2GenesisOverrides{
				FundDevAccounts:                          true,
				BaseFeeVaultMinimumWithdrawalAmount:      (*hexutil.Big)(hexutil.MustDecodeBig("0x1234")),
				L1FeeVaultMinimumWithdrawalAmount:        (*hexutil.Big)(hexutil.MustDecodeBig("0x2345")),
				SequencerFeeVaultMinimumWithdrawalAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x3456")),
				OperatorFeeVaultMinimumWithdrawalAmount:  standard.VaultMinWithdrawalAmount,
				BaseFeeVaultWithdrawalNetwork:            "remote",
				L1FeeVaultWithdrawalNetwork:              "remote",
				SequencerFeeVaultWithdrawalNetwork:       "remote",
				OperatorFeeVaultWithdrawalNetwork:        "remote",
				EnableGovernance:                         true,
				GovernanceTokenOwner:                     common.HexToAddress("0x1111111111111111111111111111111111111111"),
				NativeAssetLiquidityAmount:               (*hexutil.Big)(hexutil.MustDecodeBig("0x0")),
			},
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				sched := standard.DefaultHardforkScheduleForTag("")
				sched.L2GenesisInteropTimeOffset = op_service.U64UtilPtr(0x1234)
				return sched
			},
		},
		{
			name: "interop mode",
			intent: &state.Intent{
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"l2GenesisInteropTimeOffset": "0x0",
					"nativeAssetLiquidityAmount": "0x0",
				},
			},
			chainIntent: &state.ChainIntent{},
			expectError: false,
			expectedOverrides: func() l2GenesisOverrides {
				defaults := defaultOverrides()
				// Override with the same value that comes from JSON merge to match internal representation
				defaults.NativeAssetLiquidityAmount = (*hexutil.Big)(hexutil.MustDecodeBig("0x0"))
				return defaults
			}(),
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				schedule := standard.DefaultHardforkScheduleForTag("")
				schedule.L2GenesisInteropTimeOffset = op_service.U64UtilPtr(0)
				return schedule
			},
		},
		{
			name: "SECURITY: reject CGT override on standard chain",
			intent: &state.Intent{
				ConfigType:         state.IntentTypeStandard,
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"useCustomGasToken":          true,
					"gasPayingTokenName":         "MaliciousToken",
					"gasPayingTokenSymbol":       "MAL",
					"nativeAssetLiquidityAmount": "0x1000000",
				},
			},
			chainIntent: &state.ChainIntent{
				ID: common.HexToHash("0x1234"),
				// CustomGasToken is intentionally NOT enabled in the base intent
				CustomGasToken: state.CustomGasToken{},
			},
			expectError:       true, // Should fail security check
			expectedOverrides: l2GenesisOverrides{},
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				return nil
			},
		},
		{
			name: "allow CGT override on custom chain",
			intent: &state.Intent{
				ConfigType:         state.IntentTypeCustom,
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"useCustomGasToken":          true,
					"gasPayingTokenName":         "CustomToken",
					"gasPayingTokenSymbol":       "CTK",
					"nativeAssetLiquidityAmount": "0x1000000",
				},
			},
			chainIntent: &state.ChainIntent{
				// CustomGasToken is NOT enabled in base intent, but should be allowed for custom chains
				CustomGasToken: state.CustomGasToken{},
			},
			expectError: false, // Should succeed for custom chains
			expectedOverrides: func() l2GenesisOverrides {
				defaults := defaultOverrides()
				defaults.UseCustomGasToken = true
				defaults.GasPayingTokenName = "CustomToken"
				defaults.GasPayingTokenSymbol = "CTK"
				defaults.NativeAssetLiquidityAmount = (*hexutil.Big)(hexutil.MustDecodeBig("0x1000000"))
				return defaults
			}(),
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				return standard.DefaultHardforkScheduleForTag("")
			},
		},
		{
			name: "allow CGT override on standard-overrides chain",
			intent: &state.Intent{
				ConfigType:         state.IntentTypeStandardOverrides,
				L1ContractsLocator: &artifacts.Locator{},
				GlobalDeployOverrides: map[string]any{
					"useCustomGasToken":          true,
					"gasPayingTokenName":         "OverrideToken",
					"gasPayingTokenSymbol":       "OVR",
					"nativeAssetLiquidityAmount": "0x2000000",
					"liquidityControllerOwner":   "0x1111111111111111111111111111111111111111",
				},
			},
			chainIntent: &state.ChainIntent{
				// CustomGasToken is NOT enabled in base intent, but should be allowed for standard-overrides
				CustomGasToken: state.CustomGasToken{},
			},
			expectError: false, // Should succeed for standard-overrides chains
		expectedOverrides: func() l2GenesisOverrides {
			defaults := defaultOverrides()
			defaults.UseCustomGasToken = true
			defaults.GasPayingTokenName = "OverrideToken"
			defaults.GasPayingTokenSymbol = "OVR"
			defaults.NativeAssetLiquidityAmount = (*hexutil.Big)(hexutil.MustDecodeBig("0x2000000"))
			defaults.LiquidityControllerOwner = common.HexToAddress("0x1111111111111111111111111111111111111111")
			return defaults
		}(),
			expectedSchedule: func() *genesis.UpgradeScheduleDeployConfig {
				return standard.DefaultHardforkScheduleForTag("")
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			overrides, schedule, err := calculateL2GenesisOverrides(tc.intent, tc.chainIntent)
			if tc.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, tc.expectedOverrides, overrides)
				require.Equal(t, tc.expectedSchedule(), schedule)
			}
		})
	}
}

func TestResolveEffectiveCGT(t *testing.T) {
	testCases := []struct {
		name           string
		chainIntent    *state.ChainIntent
		overrides      l2GenesisOverrides
		expectedConfig effectiveCGTConfig
		shouldNotMutate bool
	}{
		{
			name: "CGT enabled in intent - use intent values",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{
					Name:             "Intent Token",
					Symbol:           "ITK",
					InitialLiquidity: (*hexutil.Big)(hexutil.MustDecodeBig("0x1000000")),
				},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0x1234"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Override Token",
				GasPayingTokenSymbol:       "OTK",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x2000000")),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Intent Token",
				GasPayingTokenSymbol:       "ITK",
				NativeAssetLiquidityAmount: hexutil.MustDecodeBig("0x1000000"),
				LiquidityControllerOwner:   common.HexToAddress("0x1234"),
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT not in intent but enabled in overrides - use override values",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0x5678"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Override Token",
				GasPayingTokenSymbol:       "OTK",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x3000000")),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Override Token",
				GasPayingTokenSymbol:       "OTK",
				NativeAssetLiquidityAmount: hexutil.MustDecodeBig("0x3000000"),
				LiquidityControllerOwner:   common.HexToAddress("0x5678"),
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT not in intent, override with zero liquidity - use type(uint248).max",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0xabcd"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Zero Liquidity Token",
				GasPayingTokenSymbol:       "ZLT",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x0")),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:    true,
				GasPayingTokenName:   "Zero Liquidity Token",
				GasPayingTokenSymbol: "ZLT",
				NativeAssetLiquidityAmount: func() *big.Int {
					maxUint248 := new(big.Int)
					maxUint248.SetString("00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
					return maxUint248
				}(),
				LiquidityControllerOwner: common.HexToAddress("0xabcd"),
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT not in intent, override with nil liquidity - use type(uint248).max",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0xbeef"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Nil Liquidity Token",
				GasPayingTokenSymbol:       "NLT",
				NativeAssetLiquidityAmount: nil,
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:    true,
				GasPayingTokenName:   "Nil Liquidity Token",
				GasPayingTokenSymbol: "NLT",
				NativeAssetLiquidityAmount: func() *big.Int {
					maxUint248 := new(big.Int)
					maxUint248.SetString("00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
					return maxUint248
				}(),
				LiquidityControllerOwner: common.HexToAddress("0xbeef"),
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT disabled in both intent and overrides",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0xdead"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          false,
				GasPayingTokenName:         "",
				GasPayingTokenSymbol:       "",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x0")),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:          false,
				GasPayingTokenName:         "",
				GasPayingTokenSymbol:       "",
				NativeAssetLiquidityAmount: big.NewInt(0),
				LiquidityControllerOwner:   common.Address{},
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT enabled in intent with LiquidityControllerOwner set",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{
					Name:                     "Custom Owner Token",
					Symbol:                   "COT",
					InitialLiquidity:         (*hexutil.Big)(hexutil.MustDecodeBig("0x5000000")),
					LiquidityControllerOwner: common.HexToAddress("0x9999"),
				},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0x8888"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          false,
				GasPayingTokenName:         "",
				GasPayingTokenSymbol:       "",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x0")),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Custom Owner Token",
				GasPayingTokenSymbol:       "COT",
				NativeAssetLiquidityAmount: hexutil.MustDecodeBig("0x5000000"),
				LiquidityControllerOwner:   common.HexToAddress("0x9999"),
			},
			shouldNotMutate: true,
		},
		{
			name: "CGT not in intent but enabled in overrides with explicit LiquidityControllerOwner",
			chainIntent: &state.ChainIntent{
				CustomGasToken: state.CustomGasToken{},
				Roles: state.ChainRoles{
					L2ProxyAdminOwner: common.HexToAddress("0x8888"),
				},
			},
			overrides: l2GenesisOverrides{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Override Token",
				GasPayingTokenSymbol:       "OTK",
				NativeAssetLiquidityAmount: (*hexutil.Big)(hexutil.MustDecodeBig("0x3000000")),
				LiquidityControllerOwner:   common.HexToAddress("0x7777"),
			},
			expectedConfig: effectiveCGTConfig{
				UseCustomGasToken:          true,
				GasPayingTokenName:         "Override Token",
				GasPayingTokenSymbol:       "OTK",
				NativeAssetLiquidityAmount: hexutil.MustDecodeBig("0x3000000"),
				LiquidityControllerOwner:   common.HexToAddress("0x7777"),
			},
			shouldNotMutate: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Clone the original intent to check for mutations
			originalCGT := tc.chainIntent.CustomGasToken

			// Call resolveEffectiveCGT
			result := resolveEffectiveCGT(tc.chainIntent, tc.overrides)

			// Verify result matches expected
			require.Equal(t, tc.expectedConfig.UseCustomGasToken, result.UseCustomGasToken)
			require.Equal(t, tc.expectedConfig.GasPayingTokenName, result.GasPayingTokenName)
			require.Equal(t, tc.expectedConfig.GasPayingTokenSymbol, result.GasPayingTokenSymbol)
			// Compare big.Int values numerically (not deep equality) to avoid internal representation differences
			require.True(t, tc.expectedConfig.NativeAssetLiquidityAmount.Cmp(result.NativeAssetLiquidityAmount) == 0,
				"NativeAssetLiquidityAmount mismatch: expected %s, got %s",
				tc.expectedConfig.NativeAssetLiquidityAmount.String(),
				result.NativeAssetLiquidityAmount.String())
			require.Equal(t, tc.expectedConfig.LiquidityControllerOwner, result.LiquidityControllerOwner)

			// Verify no mutation occurred
			if tc.shouldNotMutate {
				require.Equal(t, originalCGT, tc.chainIntent.CustomGasToken, "resolveEffectiveCGT should not mutate the input intent")
			}
		})
	}
}
