// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";
import { IL1Withdrawer } from "interfaces/L2/IL1Withdrawer.sol";
import { ISuperchainRevSharesCalculator } from "interfaces/L2/ISuperchainRevSharesCalculator.sol";
import { ISharesCalculator } from "interfaces/L2/ISharesCalculator.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

/// @title RevenueSharingIntegration_Test
/// @notice Integration tests for the complete revenue sharing system including
///         FeeSplitter, SuperchainRevSharesCalculator, L1Withdrawer, and FeesDepositor.
contract RevenueSharingIntegration_Test is CommonTest {
    /// @notice Basis points scale from SuperchainRevSharesCalculator
    uint32 internal constant BASIS_POINT_SCALE = 10_000;
    uint32 internal constant GROSS_SHARE_BPS = 250; // 2.5%
    uint32 internal constant NET_SHARE_BPS = 1_500; // 15%

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
        IFeeVault(payable(address(sequencerFeeVault))).setMinWithdrawalAmount(0);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(baseFeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(baseFeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(baseFeeVault))).setMinWithdrawalAmount(0);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(l1FeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(l1FeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(l1FeeVault))).setMinWithdrawalAmount(0);

        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(operatorFeeVault))).setRecipient(address(feeSplitter));
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(operatorFeeVault))).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);
        vm.prank(proxyAdminOwner);
        IFeeVault(payable(address(operatorFeeVault))).setMinWithdrawalAmount(0);
    }

    /// @notice Helper to fund vaults
    function _fundVaults(
        uint256 _sequencerFees,
        uint256 _baseFees,
        uint256 _l1Fees,
        uint256 _operatorFees
    ) private {
        vm.deal(address(sequencerFeeVault), _sequencerFees);
        vm.deal(address(baseFeeVault), _baseFees);
        vm.deal(address(l1FeeVault), _l1Fees);
        vm.deal(address(operatorFeeVault), _operatorFees);
    }

    /// @notice Helper to advance time past the fee disbursement interval
    function _advanceTimeForDisbursement() private {
        // Default fee disbursement interval is 1 day
        vm.warp(block.timestamp + 1 days + 1);
    }

    /// @notice Helper to disburse fees and advance time past the fee disbursement interval
    function _disburseFees() private {
        _advanceTimeForDisbursement();
        feeSplitter.disburseFees();
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
        // Fund all vaults with amounts
        _fundVaults(_sequencerFees, _baseFees, _l1Fees, _operatorFees);

        // Disburse fees and advance time past the fee disbursement interval
        _disburseFees();
    }

    /// @notice Helper to assert the state of all accounts in the revenue sharing flow
    /// @param sequencerFeeBalance Expected balance of sequencer fee vault
    /// @param baseFeeBalance Expected balance of base fee vault  
    /// @param l1FeeBalance Expected balance of L1 fee vault
    /// @param operatorFeeBalance Expected balance of operator fee vault
    /// @param l1WithdrawerBalance Expected balance of L1Withdrawer
    /// @param chainFeesRecipientBalance Expected balance of ChainFeesRecipient
    /// @param feesDepositorBalance Expected balance of FeesDepositor
    function _assertFullFlowState(
        uint256 sequencerFeeBalance,
        uint256 baseFeeBalance,
        uint256 l1FeeBalance,
        uint256 operatorFeeBalance,
        uint256 l1WithdrawerBalance,
        uint256 chainFeesRecipientBalance,
        uint256 feesDepositorBalance,
    ) private {
        // Assert vault balances
        assertEq(address(sequencerFeeVault).balance, sequencerFeeBalance, "Incorrect sequencer fee vault balance");
        assertEq(address(baseFeeVault).balance, baseFeeBalance, "Incorrect base fee vault balance");
        assertEq(address(l1FeeVault).balance, l1FeeBalance, "Incorrect L1 fee vault balance");
        assertEq(address(operatorFeeVault).balance, operatorFeeBalance, "Incorrect operator fee vault balance");

        // Assert recipient balances
        assertEq(address(l1Withdrawer).balance, l1WithdrawerBalance, "Incorrect L1Withdrawer balance");
        assertEq(address(chainFeesRecipient).balance, chainFeesRecipientBalance, "Incorrect ChainFeesRecipient balance");
        assertEq(address(l1FeesDepositor).balance, feesDepositorBalance, "Incorrect FeesDepositor balance");
    }

    // Full Revenue Sharing Integration Flow Test
    // Vaults: S=Sequencer, B=Base, L=L1, O=Operator
    // RevSharesCalculator recipients: L1Withdrawer (share), ChainFeesRecipient (remainder)
    // Thresholds: L1Withdrawer=10 ETH, FeesDepositor=20 ETH
    //  ________________________________________________________________________________________________
    // | Vaults (S/B/L/O) | L1Withdrawer | ChainFeesRec | FeesDepositor | Notes          |
    // |===============================================================================================|
    // | Initial state                                                                                 |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 0/0/0/0          | 0            | 0            | 0             |                |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 1. Fund vaults: S=10, B=8, L=2, O=5 ETH                                                       |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 10/8/2/5         | 0            | 0            | 0             |                |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 2. Call feeSplitter.disburseFees()                                                            |
    // |    L1Withdrawer receives 3.45 ETH < 10 ETH threshold                                          |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 0/0/0/0          | 3.45         | 21.55        | 0             |                | Accumulating   |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 3. Fund vaults: S=40, B=30, L=10, O=20 ETH                                                    |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 40/30/10/20      | 3.45         | 21.55        | 0             |                |                |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 4. Call feeSplitter.disburseFees()                                                            |
    // |    L1Withdrawer balance: 3.45 + 13.5 = 16.95 ETH > 10 ETH                                     |
    // |    Triggers withdrawal to FeesDepositor                                                       |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 0/0/0/0          | 0            | 108.05       | 16.95         |                | L2→L1 triggered|
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 5. Fund vaults: S=50, B=35, L=5, O=30 ETH                                                     |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 50/35/5/30       | 0            | 108.05       | 16.95         |                |                |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 6. Call feeSplitter.disburseFees()                                                            |
    // |    L1Withdrawer receives 17.25 ETH > 10 ETH threshold                                         |
    // |    FeesDepositor balance: 16.95 + 17.25 = 34.2 ETH > 20 ETH                                   |
    // |    Triggers deposit to OP Treasury                                                            |
    // |------------------|--------------|--------------|---------------|-------------|----------------|
    // | 0/0/0/0          | 0            | 210.8        | 0             |                | L1→L2 deposit  |
    // |__________________|______________|______________|_______________|_____________|________________|
    function test_revenueSharing_fullFlow_succeeds() public {

        // Configure vaults to withdraw to FeeSplitter
        _configureVaultsForFeeSplitter();

        // Get recipient addresses
        address shareRecipient = superchainRevSharesCalculator.shareRecipient();
        address remainderRecipient = superchainRevSharesCalculator.remainderRecipient();

        // Fund vaults with test amounts
        uint256[4] memory fees;
        fees[0] = 10 ether; // sequencer
        fees[1] = 8 ether; // base
        fees[2] = 2 ether; // l1
        fees[3] = 5 ether; // operator

        // Step 1: Fund vaults with small amounts
        _fundVaults(fees[0], fees[1], fees[2], fees[3]);

        // Step 2: First disbursement - should accumulate in L1Withdrawer
        _disburseFees();

        // Calculate expected values: Gross=25, Net=23, Share=max(0.625, 3.45)=3.45
        uint256 expectedShare1 = (23 ether * uint256(NET_SHARE_BPS)) / BASIS_POINT_SCALE; // 3.45 ETH (net > gross)
        uint256 expectedRemainder1 = 25 ether - expectedShare1; // 21.55 ETH

        // Assert state
        // Vaults: 0/0/0/0 
        //L1Withdrawer: 3.45
        //ChainFeesRecipient: 21.55
        //FeesDepositor: 0
        _assertFullFlowState(0, 0, 0, 0, expectedShare1, expectedRemainder1, 0, 0);

        // Store remainder balance for later comparison
        uint256 remainderAfterFirst = remainderRecipient.balance;

        // Step 3: Fund vaults with larger amounts
        fees[0] = 40 ether; // sequencer
        fees[1] = 30 ether; // base
        fees[2] = 10 ether; // l1
        fees[3] = 20 ether; // operator

        _fundVaults(fees[0], fees[1], fees[2], fees[3]);

        // Calculate expected values: Gross=100, Net=90, Share=max(2.5, 13.5)=13.5
        uint256 expectedShare2 = (90 ether * uint256(NET_SHARE_BPS)) / BASIS_POINT_SCALE; // 13.5 ETH (net > gross)
        uint256 expectedRemainder2 = 100 ether - expectedShare2; // 86.5 ETH
        uint256 expectedTotalWithdrawal = expectedShare1 + expectedShare2; // 16.95 ETH

        // Expect L2→L1 withdrawal since 16.95 ETH > 10 ETH threshold
        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            expectedTotalWithdrawal,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (l1Withdrawer.recipient(), l1Withdrawer.withdrawalGasLimit(), hex""))
        );

        // Step 4: Second disbursement - should trigger L2→L1 withdrawal
        _disburseFees();

        // L2ToL1MessagePasser should hold the withdrawn funds
        assertEq(address(l2ToL1MessagePasser).balance, expectedTotalWithdrawal, "L2ToL1MessagePasser should hold 16.95 ETH");

        // Mock the L1 withdrawal completing - funds reduced from L2ToL1MessagePasser and sent to FeesDepositor
        vm.deal(address(l2ToL1MessagePasser), address(l2ToL1MessagePasser).balance - expectedTotalWithdrawal);
        address(l1FeesDepositor).call{ value: expectedTotalWithdrawal }("");

        // Assert state
        // Vaults: 0/0/0/0 
        //L1Withdrawer: 3.45
        //ChainFeesRecipient: 21.55
        //FeesDepositor: 16.95
        _assertFullFlowState(0, 0, 0, 0, 0, remainderAfterFirst + expectedRemainder2, expectedTotalWithdrawal, 0);

        // Store remainder balance for final comparison
        uint256 remainderAfterSecond = remainderRecipient.balance;

        // Step 5: Fund vaults again
        fees[0] = 50 ether; // sequencer
        fees[1] = 35 ether; // base
        fees[2] = 5 ether; // l1
        fees[3] = 30 ether; // operator

        _fundVaults(fees[0], fees[1], fees[2], fees[3]);

       // Step 6: Third disbursement - should trigger L2→L1 withdrawal and then L1→L2 deposit

        // Calculate expected values: Gross=120, Net=115, Share=max(3, 17.25)=17.25
        uint256 expectedShare3 = (115 ether * uint256(NET_SHARE_BPS)) / BASIS_POINT_SCALE; // 17.25 ETH (net > gross)
        uint256 expectedRemainder3 = 120 ether - expectedShare3; // 102.75 ETH
        uint256 expectedFeesDepositorTotal = expectedShare3 + expectedShare2 + expectedShare1; // 34.2 ETH

        _disburseFees();

        //L2ToL1MessagePasser should hold the withdrawn funds
        assertEq(address(l2ToL1MessagePasser).balance, expectedShare3, "L2ToL1MessagePasser should hold 17.25 ETH");

        // Mock the L1 withdrawal completing - funds reduced from L2ToL1MessagePasser and sent to FeesDepositor
        vm.deal(address(l2ToL1MessagePasser), address(l2ToL1MessagePasser).balance - expectedShare3);
        address(l1FeesDepositor).call{ value: expectedShare3 }("");

        // Final assertions: 0/0/0/0 | 0 | 210.8 | 34.2 |
        _assertFullFlowState(0, 0, 0, 0, 0, remainderAfterSecond + expectedRemainder3, expectedFeesDepositorTotal, 0);
       }
}