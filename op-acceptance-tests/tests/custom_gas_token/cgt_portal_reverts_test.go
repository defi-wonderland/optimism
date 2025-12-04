package custom_gas_token

import (
	"context"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum-optimism/optimism/op-devstack/devtest"
	"github.com/ethereum-optimism/optimism/op-devstack/presets"
	"github.com/ethereum-optimism/optimism/op-service/txintent/bindings"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
)

// TestCGT_PortalReceiveReverts asserts that sending ETH to the L1 OptimismPortal
// (receive() -> depositTransaction) reverts under CGT, preventing ETH from getting stuck.
func TestCGT_PortalReceiveReverts(gt *testing.T) {
	t := devtest.SerialT(gt)
	sys := presets.NewMinimal(t)
	ensureCGTOrSkip(t, sys)

	l1c := sys.L1EL.EthClient()
	portal := sys.L2Chain.DepositContractAddr()

	ctx, cancel := context.WithTimeout(t.Ctx(), 20*time.Second)
	defer cancel()

	_, err := l1c.EstimateGas(ctx, ethereum.CallMsg{
		To:    &portal,
		Value: common.Big1,
	})
	if err == nil {
		t.Require().Fail("expected L1 Portal to revert on direct ETH send in CGT mode")
	}
}

// TestCGT_PortalProveWithdrawalReverts asserts that proveWithdrawalTransaction reverts
// when called with a withdrawal that has value > 0 under CGT mode.
func TestCGT_PortalProveWithdrawalReverts(gt *testing.T) {
	t := devtest.SerialT(gt)
	sys := presets.NewMinimal(t)
	ensureCGTOrSkip(t, sys)

	ctx, cancel := context.WithTimeout(t.Ctx(), 20*time.Second)
	defer cancel()

	l1Portal := newL1PortalBinding(t, sys)
	withdrawalTx := newWithdrawalTxWithValue(1)

	call := l1Portal.ProveWithdrawalTransaction(
		withdrawalTx,
		big.NewInt(0),
		bindings.OutputRootProof{},
		[][]byte{},
	)

	calldata, err := call.EncodeInput()
	if err != nil {
		t.Require().Fail("failed to encode proveWithdrawalTransaction input: %v", err)
	}

	portalAddr := sys.L2Chain.DepositContractAddr()
	_, err = sys.L1EL.EthClient().EstimateGas(ctx, ethereum.CallMsg{
		To:   &portalAddr,
		Data: calldata,
	})
	if err == nil {
		t.Require().Fail("expected proveWithdrawalTransaction to revert with value > 0 in CGT mode")
	}
}

// TestCGT_PortalFinalizeWithdrawalReverts asserts that finalizeWithdrawalTransaction reverts
// when called with a withdrawal that has value > 0 under CGT mode.
func TestCGT_PortalFinalizeWithdrawalReverts(gt *testing.T) {
	t := devtest.SerialT(gt)
	sys := presets.NewMinimal(t)
	ensureCGTOrSkip(t, sys)

	ctx, cancel := context.WithTimeout(t.Ctx(), 20*time.Second)
	defer cancel()

	l1Portal := newL1PortalBinding(t, sys)
	withdrawalTx := newWithdrawalTxWithValue(1)

	call := l1Portal.FinalizeWithdrawalTransaction(withdrawalTx)

	calldata, err := call.EncodeInput()
	if err != nil {
		t.Require().Fail("failed to encode finalizeWithdrawalTransaction input: %v", err)
	}

	portalAddr := sys.L2Chain.DepositContractAddr()
	_, err = sys.L1EL.EthClient().EstimateGas(ctx, ethereum.CallMsg{
		To:   &portalAddr,
		Data: calldata,
	})
	if err == nil {
		t.Require().Fail("expected finalizeWithdrawalTransaction to revert with value > 0 in CGT mode")
	}
}
