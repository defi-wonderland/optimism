// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";
import { IL1Withdrawer } from "interfaces/L2/IL1Withdrawer.sol";
import { ISuperchainRevSharesCalculator } from "interfaces/L2/ISuperchainRevSharesCalculator.sol";
import { ISharesCalculator } from "interfaces/L2/ISharesCalculator.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

/// @title RevenueSharingIntegration_Test
/// @notice Integration tests for the complete revenue sharing system including
///         FeeSplitter, SuperchainRevSharesCalculator, L1Withdrawer, and FeesDepositor.
contract RevenueSharingIntegration_Test is CommonTest {
    /// @notice Basis points scale from SuperchainRevSharesCalculator
    uint32 constant BASIS_POINT_SCALE = 10_000;
    uint32 constant GROSS_SHARE_BPS = 250; // 2.5%
    uint32 constant NET_SHARE_BPS = 1_500; // 15%

    event FeesDisbursed(ISharesCalculator.ShareInfo[] shareInfo, uint256 grossRevenue);
    event FeesReceived(address indexed sender, uint256 amount);
    event WithdrawalInitiated(address indexed recipient, uint256 amount);
    event FundsReceived(address indexed sender, uint256 amount, uint256 newBalance);

    function setUp() public override {
        // Enable revenue sharing before calling parent setUp
        super.enableRevenueShare();
        super.setUp();
    }

    /// @notice Configure all vaults to withdraw to FeeSplitter on L2
    function _configureVaultsForFeeSplitter() private {
        // Get the ProxyAdmin owner to configure vaults
        address proxyAdminOwner = proxyAdmin.owner();

        // Configure all vaults to withdraw to FeeSplitter on L2
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(sequencerFeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(sequencerFeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(baseFeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(baseFeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(l1FeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(l1FeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(operatorFeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(operatorFeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);
    }

    /// @notice Helper to fund vaults and trigger disbursement through FeeSplitter
    function _fundVaultsAndDisburse(
        uint256 _sequencerFees,
        uint256 _baseFees,
        uint256 _l1Fees,
        uint256 _operatorFees
    )
        private
    {
        // Configure vaults first
        _configureVaultsForFeeSplitter();

        // Fund all vaults with amounts
        vm.deal(address(sequencerFeeVault), _sequencerFees);
        vm.deal(address(baseFeeVault), _baseFees);
        vm.deal(address(l1FeeVault), _l1Fees);
        vm.deal(address(operatorFeeVault), _operatorFees);

        // Advance time to allow disbursement
        _advanceTimeForDisbursement();

        // Trigger the disbursement process
        feeSplitter.disburseFees();
    }

    /// @notice Helper to advance time past the fee disbursement interval
    function _advanceTimeForDisbursement() private {
        // Default fee disbursement interval is 1 day
        vm.warp(block.timestamp + 1 days + 1);
    }

    function test_feeSplitter_distributesToL2Recipients_succeeds() public {
        // Fund vaults with test amounts (gross revenue = 100 ETH)
        uint256[4] memory fees;
        fees[0] = 40 ether; // sequencer
        fees[1] = 30 ether; // base
        fees[2] = 10 ether; // l1
        fees[3] = 20 ether; // operator
        _fundVaultsAndDisburse(fees[0], fees[1], fees[2], fees[3]);

        uint256 grossRevenue = fees[0] + fees[1] + fees[2] + fees[3]; // 100 ETH
        uint256 netRevenue = grossRevenue - fees[2]; // 90 ETH (gross - L1 fees)
        uint256 grossShare = (grossRevenue * GROSS_SHARE_BPS) / BASIS_POINT_SCALE; // 2.5 ETH
        uint256 netShare = (netRevenue * NET_SHARE_BPS) / BASIS_POINT_SCALE; // 13.5 ETH
        uint256 expectedShare = netShare > grossShare ? netShare : grossShare; // max(13.5, 2.5) = 13.5 ETH
        uint256 expectedRemainderAmount = grossRevenue - expectedShare; // 86.5 ETH

        // Get the share and remainder recipients
        address shareRecipient = superchainRevSharesCalculator.shareRecipient();
        address remainderRecipient = superchainRevSharesCalculator.remainderRecipient();

        // Note: shareRecipient (L1Withdrawer) balance is 0 because it automatically withdrew to L1
        // The funds should be in the L2ToL1MessagePasser
        assertEq(shareRecipient.balance, 0, "L1Withdrawer should have withdrawn funds");
        assertEq(remainderRecipient.balance, expectedRemainderAmount, "Remainder recipient incorrect amount");

        // Verify L2ToL1MessagePasser received the withdrawal
        assertEq(address(l2ToL1MessagePasser).balance, expectedShare, "L2ToL1MessagePasser should have withdrawal funds");
    }
}