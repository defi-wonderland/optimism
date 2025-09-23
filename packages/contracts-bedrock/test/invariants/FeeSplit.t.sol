// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { StdUtils } from "forge-std/StdUtils.sol";
import { Vm } from "forge-std/Vm.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { InvariantTest } from "test/invariants/InvariantTest.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";

/// @notice A struct to keep track of the state when a disburse call fails
struct DisburseFailureState {
    uint256 sequencerFeeVaultBalance;
    uint256 baseFeeVaultBalance;
    uint256 l1FeeVaultBalance;
    uint256 operatorFeeVaultBalance;
    uint256 attemptTimestamp;
}

/// @title Handler to call the disburseFees function
contract FeeSplitter_Disburser is StdUtils {
    /// @notice Vm instance
    Vm internal vm;

    /// @notice FeeSplitter contract
    IFeeSplitter public feeSplitter;

    /// @notice Flag to track if a disburseFees() call failed
    bool public txFailed;

    /// @notice Keep track of the balances and timestamp of a failed disbursement
    DisburseFailureState internal failureState;

    /// @notice Aggregate of the vault balances disbursed
    uint256 public ghost_grossRevenueDisbursed;

    constructor(Vm _vm, IFeeSplitter _feeSplitter) {
        vm = _vm;
        feeSplitter = _feeSplitter;
    }

    /// @notice Get the failure state (convenience, to keep the struct)
    function getFailureState() external view returns (DisburseFailureState memory failureState_) {
        failureState_ = failureState;
    }

    /// @notice handler for FeeSplitter.disburseFees()
    /// @dev It update important ghost var, in both success and failure cases:
    /// - success: update the overall amount disbursed (ie add the sum of the vaults balances before disbursement)
    /// - failure: update the failure state (all vault balances and the current timestamp)
    function disburse() public {
        uint256 _aggregateVaultsBalances = address(Predeploys.SEQUENCER_FEE_WALLET).balance
            + address(Predeploys.BASE_FEE_VAULT).balance + address(Predeploys.L1_FEE_VAULT).balance
            + address(Predeploys.OPERATOR_FEE_VAULT).balance;

        try feeSplitter.disburseFees() {
            // reset the fail flags
            txFailed = false;
            delete failureState;

            ghost_grossRevenueDisbursed += _aggregateVaultsBalances;
        } catch {
            // keep track of the failing state
            txFailed = true;
            failureState.sequencerFeeVaultBalance = address(Predeploys.SEQUENCER_FEE_WALLET).balance;
            failureState.baseFeeVaultBalance = address(Predeploys.BASE_FEE_VAULT).balance;
            failureState.l1FeeVaultBalance = address(Predeploys.L1_FEE_VAULT).balance;
            failureState.operatorFeeVaultBalance = address(Predeploys.OPERATOR_FEE_VAULT).balance;
            failureState.attemptTimestamp = block.timestamp;
        }
    }
}

/// @title Handler to set arbitrary preconditions (balance and block timestamp)
contract FeeSplitter_Preconditions is CommonTest {
    /// @notice Warp the block timestamp
    /// @param _seconds The seed of the seconds to warp the block timestamp by
    function warp(uint256 _seconds) public {
        _seconds = bound(_seconds, 0, 10 days);
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Add collected fee to a vault
    /// @param _amount The seed of amount to add to the vault
    /// @param _vaultIndex The seed of the vault's index to add the fee to
    /// @dev The gross revenue has an upper bound to avoid overflows in the shares calculator (where
    /// `uint256 netShare = (netRevenue * uint256(NET_SHARE_BPS)) / BASIS_POINT_SCALE;` would overflow
    /// otherwise)
    function addCollectedFeeToVault(uint256 _amount, uint256 _vaultIndex) public {
        _vaultIndex = bound(_vaultIndex, 0, 3);

        // Avoid having the net revenue exceeding the max uint256 / 1500 (net share default is 1500 bps in the
        // superchain rev shares calculator)
        _amount = bound(
            _amount,
            0,
            (type(uint256).max / 1500) - address(Predeploys.SEQUENCER_FEE_WALLET).balance
                - address(Predeploys.BASE_FEE_VAULT).balance - address(Predeploys.OPERATOR_FEE_VAULT).balance
        );

        if (_vaultIndex == 0) {
            vm.deal(address(Predeploys.SEQUENCER_FEE_WALLET), _amount);
        } else if (_vaultIndex == 1) {
            vm.deal(address(Predeploys.BASE_FEE_VAULT), _amount);
        } else if (_vaultIndex == 2) {
            vm.deal(address(Predeploys.L1_FEE_VAULT), _amount);
        } else if (_vaultIndex == 3) {
            vm.deal(address(Predeploys.OPERATOR_FEE_VAULT), _amount);
        }
    }
}

/// @title Invariants for the FeeSplitter
/// @notice The invariants tested are:
/// - no dust accumulation in the FeeSplitter
/// - total disbursed fees should always be equal to the sum of the vault balances before disbursement
/// - disburseFees can only revert if either one of the vault has a balance below it's minimum withdrawal amount
///   or if the disbursement interval has not been reached yet
/// @dev These invariants are covering the system formed by:
/// FeeSplitter, 4 FeeVault's, SuperchainRevSharesCalculator, L1Withdrawer
contract FeeSplitter_Invariant is CommonTest {
    /// @notice Handler for disbursing fees
    FeeSplitter_Disburser public disburser;

    /// @notice Handler to set test preconditions
    FeeSplitter_Preconditions public preconditions;

    /// @notice Setup: enable the revenue share, deploy handlers and target them.
    function setUp() public override {
        super.enableRevenueShare();
        super.setUp();

        IFeeSplitter feeSplitter = IFeeSplitter(payable(Predeploys.FEE_SPLITTER));

        disburser = new FeeSplitter_Disburser(vm, feeSplitter);
        preconditions = new FeeSplitter_Preconditions();

        targetContract(address(disburser));

        targetContract(address(preconditions));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = FeeSplitter_Preconditions.warp.selector;
        selectors[1] = FeeSplitter_Preconditions.addCollectedFeeToVault.selector;
        targetSelector(FuzzSelector({ addr: address(preconditions), selectors: selectors }));
    }

    /// @notice Invariant: The fee splitter balance should always be 0
    /// @dev This invariant doesn't account for direct forced transfers (eg selfdestruct)
    function invariant_noDust() external view {
        assertEq(address(disburser.feeSplitter()).balance, 0);
    }

    /// @notice Invariant: The total disbursed fees should always be equal to the sum of the vault balances before
    /// disbursement
    /// @dev This invariant can also be expressed as "disburseFees is only successful if all vaults can transfer the
    /// fee/all or nothing (0 threshold is accepted)" as, otherwise, some funds would still be in the vaults,
    /// invalidating the equality
    function invariant_balanceConservation() external view {
        assertEq(
            disburser.ghost_grossRevenueDisbursed(),
            address(l1Withdrawer).balance + l1Withdrawer.recipient().balance
                + Predeploys.L2_TO_L1_MESSAGE_PASSER.balance + address(chainFeesRecipient).balance
        );
    }

    /// @notice Invariants: these are revert invariants, disburseFees can only revert if either one of the vault
    /// has a balance below it's minimum withdrawal amount (no other revert conditions are possible for the vault)
    /// or if the disbursement interval has not been reached yet.
    /// @dev This invariant is also testing the "no partial disbursement", as the previous one.
    function invariant_disburseReverts() external view {
        if (disburser.txFailed()) {
            DisburseFailureState memory _failureState = disburser.getFailureState();

            assertTrue(
                // either one of the vaults is below the minimum withdrawal amount
                _failureState.sequencerFeeVaultBalance
                    < IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).minWithdrawalAmount()
                    || _failureState.baseFeeVaultBalance
                        < IFeeVault(payable(Predeploys.BASE_FEE_VAULT)).minWithdrawalAmount()
                    || _failureState.l1FeeVaultBalance < IFeeVault(payable(Predeploys.L1_FEE_VAULT)).minWithdrawalAmount()
                    || _failureState.operatorFeeVaultBalance
                        < IFeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).minWithdrawalAmount()
                // not enough time since last disbursement
                || _failureState.attemptTimestamp
                    < disburser.feeSplitter().lastDisbursementTime() + disburser.feeSplitter().feeDisbursementInterval()
            );
        }
    }
}
