package state

import (
	"math/big"
	"testing"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/standard"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/stretchr/testify/require"
)

func TestCombineDeployConfig(t *testing.T) {
	intent := Intent{
		L1ChainID:          1,
		L1ContractsLocator: artifacts.MustNewLocatorFromTag(standard.ContractsV170Beta1L2Tag),
	}
	chainState := ChainState{
		ID: common.HexToHash("0x123"),
	}
	chainIntent := ChainIntent{
		Eip1559Denominator:                       1,
		Eip1559Elasticity:                        2,
		BaseFeeVaultRecipient:                    common.HexToAddress("0x123"),
		L1FeeVaultRecipient:                      common.HexToAddress("0x456"),
		SequencerFeeVaultRecipient:               common.HexToAddress("0x789"),
		OperatorFeeVaultRecipient:                common.HexToAddress("0xabc"),
		BaseFeeVaultMinimumWithdrawalAmount:      (*hexutil.Big)(big.NewInt(10)),
		L1FeeVaultMinimumWithdrawalAmount:        (*hexutil.Big)(big.NewInt(10)),
		SequencerFeeVaultMinimumWithdrawalAmount: (*hexutil.Big)(big.NewInt(10)),
		OperatorFeeVaultMinimumWithdrawalAmount:  (*hexutil.Big)(big.NewInt(10)),
		BaseFeeVaultWithdrawalNetwork:            "remote",
		L1FeeVaultWithdrawalNetwork:              "remote",
		SequencerFeeVaultWithdrawalNetwork:       "remote",
		OperatorFeeVaultWithdrawalNetwork:        "remote",
		Roles: ChainRoles{
			SystemConfigOwner:    common.HexToAddress("0x123"),
			L1ProxyAdminOwner:    common.HexToAddress("0x456"),
			L2ProxyAdminOwner:    common.HexToAddress("0x789"),
			UnsafeBlockSigner:    common.HexToAddress("0xabc"),
			Batcher:              common.HexToAddress("0xdef"),
			SystemConfigFeeAdmin: common.HexToAddress("0x123"),
		},
	}
	state := State{
		SuperchainDeployment: &SuperchainDeployment{ProtocolVersionsProxyAddress: common.HexToAddress("0x123")},
	}

	// apply hard fork overrides
	chainIntent.DeployOverrides = map[string]any{
		"l2GenesisGraniteTimeOffset":  "0x8",
		"l2GenesisHoloceneTimeOffset": "0x10",
	}

	out, err := CombineDeployConfig(&intent, &chainIntent, &state, &chainState)
	require.NoError(t, err)
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisFjordTimeOffset, hexutil.Uint64(0))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisGraniteTimeOffset, hexutil.Uint64(8))
	require.Equal(t, *out.L2InitializationConfig.UpgradeScheduleDeployConfig.L2GenesisHoloceneTimeOffset, hexutil.Uint64(16))
}
