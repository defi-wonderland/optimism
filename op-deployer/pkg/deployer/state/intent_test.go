package state

import (
	"math/big"
	"testing"

	"github.com/ethereum-optimism/optimism/op-chain-ops/addresses"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/stretchr/testify/require"
)

func TestValidateStandardValues(t *testing.T) {
	intent, err := NewIntentStandard(11155111, []common.Hash{common.HexToHash("0x336")})
	require.NoError(t, err)

	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, addresses.ErrZeroAddress)

	setChainRoles(&intent)
	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, ErrFeeVaultZeroAddress)

	setFeeAddresses(&intent)
	err = intent.Check()
	require.NoError(t, err)

	tests := []struct {
		name    string
		mutator func(intent *Intent)
		err     error
	}{
		{
			"EIP1559Denominator",
			func(intent *Intent) {
				intent.Chains[0].Eip1559Denominator = 3
			},
			ErrNonStandardValue,
		},
		{
			"EIP1559DenominatorCanyon",
			func(intent *Intent) {
				intent.Chains[0].Eip1559DenominatorCanyon = 3
			},
			ErrNonStandardValue,
		},
		{
			"EIP1559Elasticity",
			func(intent *Intent) {
				intent.Chains[0].Eip1559Elasticity = 999
			},
			ErrNonStandardValue,
		},
		{
			"AdditionalDisputeGames",
			func(intent *Intent) {
				intent.Chains[0].AdditionalDisputeGames = []AdditionalDisputeGame{
					{
						VMType: VMTypeAlphabet,
					},
				}
			},
			ErrNonStandardValue,
		},
		{
			"CustomGasToken",
			func(intent *Intent) {
				intent.Chains[0].CustomGasToken = &CustomGasToken{
					Enabled: false,
					Name:    "",
					Symbol:  "",
				}
			},
			ErrNonStandardValue,
		},
		{
			"SuperchainConfigProxy",
			func(intent *Intent) {
				addr := common.HexToAddress("0x9999")
				intent.SuperchainConfigProxy = &addr
			},
			ErrIncompatibleValue,
		},
		{
			"OPCMAddress",
			func(intent *Intent) {
				addr := common.HexToAddress("0x9999")
				intent.OPCMAddress = &addr
			},
			ErrNonStandardValue,
		},
		{
			"SuperchainRoles",
			func(intent *Intent) {
				intent.SuperchainRoles = &addresses.SuperchainRoles{
					SuperchainGuardian: common.HexToAddress("0x9999"),
				}
			},
			ErrIncompatibleValue,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			intent, err := NewIntentStandard(11155111, []common.Hash{common.HexToHash("0x336")})
			require.NoError(t, err)
			setChainRoles(&intent)
			setFeeAddresses(&intent)

			tt.mutator(&intent)

			err = intent.Check()
			require.Error(t, err)
			require.ErrorIs(t, err, tt.err)
		})
	}
}

func TestValidateCustomValues(t *testing.T) {
	intent, err := NewIntentCustom(1, []common.Hash{common.HexToHash("0x336")})
	require.NoError(t, err)

	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, addresses.ErrZeroAddress)

	setSuperchainRoles(&intent)
	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, addresses.ErrZeroAddress)

	setChainRoles(&intent)
	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, ErrEip1559ZeroValue)

	setEip1559Params(&intent)
	err = intent.Check()
	require.Error(t, err)
	require.ErrorIs(t, err, ErrFeeVaultZeroAddress)

	setFeeAddresses(&intent)
	err = intent.Check()
	require.NoError(t, err)

	setCustomGasToken(&intent)
	err = intent.Check()
	require.NoError(t, err)

	tests := []struct {
		name    string
		mutator func(intent *Intent)
		err     error
	}{
		{
			"both OPCM and SuperchainRoles defined",
			func(intent *Intent) {
				addr := common.HexToAddress("0x9999")
				intent.SuperchainRoles = &addresses.SuperchainRoles{
					SuperchainGuardian: addr,
				}
				intent.OPCMAddress = &addr
			},
			ErrIncompatibleValue,
		},
		{
			"neither OPCM or SuperchainRoles defined",
			func(intent *Intent) {
				intent.OPCMAddress = nil
				intent.SuperchainRoles = nil
			},
			ErrIncompatibleValue,
		},
		{
			"empty custom gas token name when enabled",
			func(intent *Intent) {
				intent.Chains[0].CustomGasToken = &CustomGasToken{
					Enabled: true,
					Name:    "",
					Symbol:  "CGT",
				}
			},
			ErrIncompatibleValue,
		},
		{
			"empty custom gas token symbol when enabled",
			func(intent *Intent) {
				intent.Chains[0].CustomGasToken = &CustomGasToken{
					Enabled: true,
					Name:    "Custom Gas Token",
					Symbol:  "",
				}
			},
			ErrIncompatibleValue,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			intent, err := NewIntentCustom(11155111, []common.Hash{common.HexToHash("0x336")})
			require.NoError(t, err)

			setSuperchainRoles(&intent)
			setChainRoles(&intent)

			setEip1559Params(&intent)
			setFeeAddresses(&intent)

			tt.mutator(&intent)

			err = intent.Check()
			require.Error(t, err)
			require.ErrorIs(t, err, tt.err)
		})
	}
}

func setSuperchainRoles(intent *Intent) {
	intent.SuperchainRoles = &addresses.SuperchainRoles{
		SuperchainProxyAdminOwner: common.HexToAddress("0xa"),
		ProtocolVersionsOwner:     common.HexToAddress("0xb"),
		SuperchainGuardian:        common.HexToAddress("0xc"),
		Challenger:                common.HexToAddress("0xd"),
	}
}

func setEip1559Params(intent *Intent) {
	intent.Chains[0].Eip1559Denominator = 5000
	intent.Chains[0].Eip1559DenominatorCanyon = 5000
	intent.Chains[0].Eip1559Elasticity = 5000
}

func setChainRoles(intent *Intent) {
	if intent.Chains[0].Roles.L1ProxyAdminOwner == (common.Address{}) {
		intent.Chains[0].Roles.L1ProxyAdminOwner = common.HexToAddress("0x01")
	}
	if intent.Chains[0].Roles.Challenger == (common.Address{}) {
		intent.Chains[0].Roles.Challenger = common.HexToAddress("0x07")
	}

	intent.Chains[0].Roles.L2ProxyAdminOwner = common.HexToAddress("0x02")
	intent.Chains[0].Roles.SystemConfigOwner = common.HexToAddress("0x03")
	intent.Chains[0].Roles.UnsafeBlockSigner = common.HexToAddress("0x04")
	intent.Chains[0].Roles.Batcher = common.HexToAddress("0x05")
	intent.Chains[0].Roles.Proposer = common.HexToAddress("0x06")
}

func setFeeAddresses(intent *Intent) {
	intent.Chains[0].BaseFeeVaultRecipient = common.HexToAddress("0x08")
	intent.Chains[0].L1FeeVaultRecipient = common.HexToAddress("0x09")
	intent.Chains[0].SequencerFeeVaultRecipient = common.HexToAddress("0x0A")
}

func setCustomGasToken(intent *Intent) {
	// Each chain configures its own liquidity amount based on their needs
	// Example: This test chain decides to use 1000 ETH as their liquidity pool
	liquidityAmount := EtherToWei(1000) // 1000 ETH

	intent.Chains[0].CustomGasToken = &CustomGasToken{
		Enabled: true,
		Name:    "Custom Gas Token",
		Symbol:  "CGT",
		CustomGasTokenLiquidityAmount: (*hexutil.Big)(liquidityAmount),
	}
}

// Example helper functions showing how different chains might configure liquidity
func setCustomGasTokenWithHighLiquidity(intent *Intent) {
	// A high-volume chain might want more liquidity (e.g., 10,000 ETH)
	liquidityAmount := EtherToWei(10000)

	intent.Chains[0].CustomGasToken = &CustomGasToken{
		Enabled: true,
		Name:    "High Volume Token",
		Symbol:  "HVT",
		CustomGasTokenLiquidityAmount: (*hexutil.Big)(liquidityAmount),
	}
}

func setCustomGasTokenWithLowLiquidity(intent *Intent) {
	// A smaller chain might use less liquidity (e.g., 100 ETH)
	liquidityAmount := EtherToWei(100)

	intent.Chains[0].CustomGasToken = &CustomGasToken{
		Enabled: true,
		Name:    "Small Chain Token",
		Symbol:  "SCT",
		CustomGasTokenLiquidityAmount: (*hexutil.Big)(liquidityAmount),
	}
}
