// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { FeeSplitter } from "src/L2/FeeSplitter.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

contract FeeSplitterTest is CommonTest {
    address private _revenueShareRecipient;
    address private _revenueRemainderRecipient;
    address private _owner;

    address private _defaultRevenueShareRecipient = address(0x1234567890123456789012345678901234567890);
    address private _defaultRevenueRemainderRecipient = address(0x0987654321098765432109876543210987654321);
    uint40 private _defaultFeeDisbursementInterval = 24 hours;
    uint16 private _defaultNetFeeShareBP = 1_500;
    uint16 private _defaultGrossFeeShareBP = 250;

    // Events
    event Initialized(
        address payable revenueShareRecipient,
        address payable revenueRemainderRecipient,
        uint40 feeDisbursementInterval,
        uint16 netFeeShareBP,
        uint16 grossFeeShareBP
    );

    event FeesDisbursed(
        address indexed revenueShareRecipient,
        address indexed revenueRemainderRecipient,
        uint256 revenueShareRecipientAmount,
        uint256 revenueRemainderRecipientAmount
    );

    event NoFeesCollected();

    /// @notice Use common test to setup the test environment
    function setUp() public override {
        super.setUp();
        _setupTestAddresses();
    }

    /// @notice Setup the test addresses
    function _setupTestAddresses() internal {
        _owner = ProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        _revenueShareRecipient = makeAddr("revenueShareRecipient");
        _revenueRemainderRecipient = makeAddr("revenueRemainderRecipient");
    }

    /// @notice Setup the mock fee vaults
    function _setupMockFeeVaults() internal {
        // Deploy mock FeeVault contracts with proper configuration
        Mock_FeeVault sequencerFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault baseFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault l1FeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault operatorFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        // Etch the mock vaults at the predeploy addresses
        vm.etch(Predeploys.SEQUENCER_FEE_WALLET, address(sequencerFeeVault).code);
        vm.etch(Predeploys.BASE_FEE_VAULT, address(baseFeeVault).code);
        vm.etch(Predeploys.L1_FEE_VAULT, address(l1FeeVault).code);
        vm.etch(Predeploys.OPERATOR_FEE_VAULT, address(operatorFeeVault).code);
    }

    /// @notice Setup mock fee vaults with invalid configuration for testing revert conditions
    function _setupMockFeeVaultsWithInvalidConfig(
        address _targetVault,
        Types.WithdrawalNetwork _withdrawalNetwork,
        address _recipient
    )
        internal
    {
        // Deploy mock FeeVault contracts with proper configuration for all vaults
        Mock_FeeVault sequencerFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault baseFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault l1FeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault operatorFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_SPLITTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        // Create a mock vault with invalid configuration for the target vault
        Mock_FeeVault invalidFeeVault = new Mock_FeeVault(
            payable(_recipient), // recipient
            1 ether, // minWithdrawalAmount
            _withdrawalNetwork // withdrawalNetwork
        );

        // Etch the mock vaults at the predeploy addresses
        vm.etch(Predeploys.SEQUENCER_FEE_WALLET, address(sequencerFeeVault).code);
        vm.etch(Predeploys.BASE_FEE_VAULT, address(baseFeeVault).code);
        vm.etch(Predeploys.L1_FEE_VAULT, address(l1FeeVault).code);
        vm.etch(Predeploys.OPERATOR_FEE_VAULT, address(operatorFeeVault).code);

        // Override the target vault with invalid configuration
        vm.etch(_targetVault, address(invalidFeeVault).code);
    }

    /// @notice test the contract cant be re-initialized
    function test_constructor_succeeds() public {
        vm.prank(_owner);
        vm.expectRevert("Initializable: contract is already initialized");
        feeSplitter.initialize(
            payable(_revenueShareRecipient),
            payable(_revenueRemainderRecipient),
            _defaultFeeDisbursementInterval,
            _defaultNetFeeShareBP,
            _defaultGrossFeeShareBP
        );
    }

    /// @notice assert the initialize function reverts when the configured share recipient is address(0)
    function test_feeSplitterInitialize_WhenInvalidRevenueShareRecipient_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_RevenueShareRecipientCannotBeZero.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(address(0)),
            payable(_revenueRemainderRecipient),
            _defaultFeeDisbursementInterval,
            10001,
            _defaultGrossFeeShareBP
        );
    }

    /// @notice assert the initialize function reverts when the remainder recipient is address(0)
    function test_feeSplitterInitialize_WhenInvalidRevenueRemainderRecipient_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_RevenueRemainderRecipientCannotBeZero.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(_revenueShareRecipient),
            payable(address(0)),
            _defaultFeeDisbursementInterval,
            10001,
            _defaultGrossFeeShareBP
        );
    }

    /// @notice assert the initialize function reverts when the fee disbursement interval is less than 24 hours
    function test_feeSplitterInitialize_WhenInvalidFeeDisbursementInterval_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeDisbursementIntervalTooShort.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(_revenueShareRecipient),
            payable(_revenueRemainderRecipient),
            1 hours,
            _defaultNetFeeShareBP,
            _defaultGrossFeeShareBP
        );
    }

    /// @notice assert the initialize function reverts when the net fee share bp is greater than 100%
    function test_feeSplitterInitialize_WhenInvalidNetFeeShareBP_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeShareBPExceeds100Percent.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(_revenueShareRecipient),
            payable(_revenueRemainderRecipient),
            _defaultFeeDisbursementInterval,
            10001,
            _defaultGrossFeeShareBP
        );
    }

    /// @notice assert the initialize function reverts when the gross fee share bp is greater than 100%
    function test_feeSplitterInitialize_WhenInvalidGrossFeeShareBP_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl3"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_GrossFeeShareBPExceeds100Percent.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(_revenueShareRecipient),
            payable(_revenueRemainderRecipient),
            _defaultFeeDisbursementInterval,
            _defaultNetFeeShareBP,
            10001
        );
    }

    /// @notice assert all addresses, fee disbursement interval, and fee share are correctly set
    function test_feeSplitter_initialization_succeeds() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.expectEmit(address(impl));
        emit Initialized({
            revenueShareRecipient: payable(_defaultRevenueShareRecipient),
            revenueRemainderRecipient: payable(_defaultRevenueRemainderRecipient),
            feeDisbursementInterval: _defaultFeeDisbursementInterval,
            netFeeShareBP: _defaultNetFeeShareBP,
            grossFeeShareBP: _defaultGrossFeeShareBP
        });

        vm.prank(_owner);
        IFeeSplitter(payable(impl)).initialize(
            payable(_defaultRevenueShareRecipient),
            payable(_defaultRevenueRemainderRecipient),
            _defaultFeeDisbursementInterval,
            _defaultNetFeeShareBP,
            _defaultGrossFeeShareBP
        );

        assertEq(IFeeSplitter(payable(impl)).revenueShareRecipient(), _defaultRevenueShareRecipient);
        assertEq(IFeeSplitter(payable(impl)).revenueRemainderRecipient(), _defaultRevenueRemainderRecipient);
        assertEq(IFeeSplitter(payable(impl)).feeDisbursementInterval(), _defaultFeeDisbursementInterval);
        assertEq(IFeeSplitter(payable(impl)).netFeeShareBP(), _defaultNetFeeShareBP);
        assertEq(IFeeSplitter(payable(impl)).grossFeeShareBP(), _defaultGrossFeeShareBP);
    }

    /// @notice assert the receive function reverts when the payout gate is closed
    function test_feeSplitterReceive_WhenPayoutGateIsClosed_Reverts() public {
        Mock_FeeSplitter feeSplitter = new Mock_FeeSplitter();
        feeSplitter.setPayoutGateState(1);

        address sender = makeAddr("sender");
        vm.deal(sender, 1 ether);
        vm.prank(sender);
        vm.expectRevert(FeeSplitter.FeeSplitter_ReceiveDisabledDuringPayout.selector);
        address(feeSplitter).call{ value: 1 ether }("");
    }

    /// @notice assert the receive function works as expected
    function test_feeSplitterReceive_WhenValidFeeVault_Succeeds() public {
        // Send ETH to the FeeSplitter from a FeeVault
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 1 ether);
        vm.prank(Predeploys.SEQUENCER_FEE_WALLET);
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was updated
        assertEq(feeSplitter.netFeeRevenue(), 1 ether);
    }

    /// @notice assert the receive function from non-FeeVault address
    function test_feeSplitterReceive_WhenNonFeeVault_Succeeds() public {
        // Send ETH to the FeeSplitter from a non-FeeVault address
        vm.deal(address(0x123), 1 ether);
        vm.prank(address(0x123));
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was NOT updated (only FeeVaults update it)
        assertEq(feeSplitter.netFeeRevenue(), 0);
    }

    /// @notice assert the receive function from L1 FeeVault does not increment net revenue
    function test_feeSplitterReceive_WhenL1FeeVault_DoesNotIncrementNetRevenue() public {
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.prank(Predeploys.L1_FEE_VAULT);
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        assertEq(feeSplitter.netFeeRevenue(), 0);
    }

    /// @notice assert the disburseFees function reverts when the fee disbursement interval has not been reached
    function test_feeSplitterDisburseFees_WhenFeeDisbursementIntervalNotReached_Reverts() public {
        vm.expectRevert(FeeSplitter.FeeSplitter_DisbursementIntervalNotReached.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when SEQUENCER_FEE_WALLET has L1 withdrawal network
    function test_feeSplitterDispurseFees_WhenSequencerFeeWalletHasL1WithdrawalNetwork_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.SEQUENCER_FEE_WALLET,
            Types.WithdrawalNetwork.L1, // Invalid: should be L2
            Predeploys.FEE_SPLITTER // Valid recipient
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToL2.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when SEQUENCER_FEE_WALLET has invalid recipient
    function test_feeSplitterDispurseFees_WhenSequencerFeeWalletHasInvalidRecipient_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.SEQUENCER_FEE_WALLET,
            Types.WithdrawalNetwork.L2, // Valid network
            address(0x123) // Invalid: should be FeeSplitter
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToFeeSplitter.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when BASE_FEE_VAULT has L1 withdrawal network
    function test_feeSplitterDispurseFees_WhenBaseFeeVaultHasL1WithdrawalNetwork_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.BASE_FEE_VAULT,
            Types.WithdrawalNetwork.L1, // Invalid: should be L2
            Predeploys.FEE_SPLITTER // Valid recipient
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToL2.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when BASE_FEE_VAULT has invalid recipient
    function test_feeSplitterDispurseFees_WhenBaseFeeVaultHasInvalidRecipient_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.BASE_FEE_VAULT,
            Types.WithdrawalNetwork.L2, // Valid network
            address(0x456) // Invalid: should be FeeSplitter
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToFeeSplitter.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when L1_FEE_VAULT has L1 withdrawal network
    function test_feeSplitterDispurseFees_WhenL1FeeVaultHasL1WithdrawalNetwork_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.L1_FEE_VAULT,
            Types.WithdrawalNetwork.L1, // Invalid: should be L2
            Predeploys.FEE_SPLITTER // Valid recipient
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToL2.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when L1_FEE_VAULT has invalid recipient
    function test_feeSplitterDispurseFees_WhenL1FeeVaultHasInvalidRecipient_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.L1_FEE_VAULT,
            Types.WithdrawalNetwork.L2, // Valid network
            address(0x789) // Invalid: should be FeeSplitter
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToFeeSplitter.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when OPERATOR_FEE_VAULT has L1 withdrawal network
    function test_feeSplitterDispurseFees_WhenOperatorFeeVaultHasL1WithdrawalNetwork_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.OPERATOR_FEE_VAULT,
            Types.WithdrawalNetwork.L1, // Invalid: should be L2
            Predeploys.FEE_SPLITTER // Valid recipient
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToL2.selector);
        feeSplitter.disburseFees();
    }

    /// @notice Test that _feeVaultWithdrawal reverts when OPERATOR_FEE_VAULT has invalid recipient
    function test_feeSplitterDispurseFees_WhenOperatorFeeVaultHasInvalidRecipient_Reverts() public {
        _setupMockFeeVaultsWithInvalidConfig(
            Predeploys.OPERATOR_FEE_VAULT,
            Types.WithdrawalNetwork.L2, // Valid network
            address(0xABC) // Invalid: should be FeeSplitter
        );

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeVaultMustWithdrawToFeeSplitter.selector);
        feeSplitter.disburseFees();
    }

    /// @notice assert the disburseFees function succeeds when no fees have been collected
    function test_feeSplitterDisburseFees_WhenNoFeesCollected_Succeeds() public {
        _setupMockFeeVaults();

        // Don't add any balances to the fee vaults
        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Expect the NoFeesCollected event to be emitted
        vm.expectEmit(address(Predeploys.FEE_SPLITTER));
        emit NoFeesCollected();

        // Expect 0 calls to withdraw on the fee vaults
        vm.expectCall(Predeploys.SEQUENCER_FEE_WALLET, abi.encodeWithSelector(Mock_FeeVault.withdraw.selector), 0);
        vm.expectCall(Predeploys.BASE_FEE_VAULT, abi.encodeWithSelector(Mock_FeeVault.withdraw.selector), 0);
        vm.expectCall(Predeploys.L1_FEE_VAULT, abi.encodeWithSelector(Mock_FeeVault.withdraw.selector), 0);
        vm.expectCall(Predeploys.OPERATOR_FEE_VAULT, abi.encodeWithSelector(Mock_FeeVault.withdraw.selector), 0);

        // Call disburseFees
        feeSplitter.disburseFees();

        // Verify the last disbursement time was NOT updated
        assertEq(feeSplitter.lastDisbursementTime(), 0);
    }

    /// @notice assert the disburseFees function succeeds when the fee disbursement interval has been reached
    function testFuzz_feeSplitterDisburseFees_succeeds(uint256 _amount) public {
        _amount = bound(_amount, 10 ether, type(uint128).max);

        _setupMockFeeVaults();

        // Add balances to the fee vaults
        uint256 _amountToSend = _amount / 4;
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, _amountToSend);
        vm.deal(Predeploys.BASE_FEE_VAULT, _amountToSend);
        vm.deal(Predeploys.L1_FEE_VAULT, _amountToSend);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, _amountToSend);

        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Calculate expected amounts using max(netShare, grossShare) from contract
        uint256 expectedGrossRevenue = address(Predeploys.SEQUENCER_FEE_WALLET).balance
            + address(Predeploys.BASE_FEE_VAULT).balance + address(Predeploys.L1_FEE_VAULT).balance
            + address(Predeploys.OPERATOR_FEE_VAULT).balance;

        uint256 expectedNetRevenue = address(Predeploys.SEQUENCER_FEE_WALLET).balance
            + address(Predeploys.BASE_FEE_VAULT).balance + address(Predeploys.OPERATOR_FEE_VAULT).balance;

        uint256 bpScale = feeSplitter.BASIS_POINT_SCALE();
        uint256 netShareBP = feeSplitter.netFeeShareBP();
        uint256 grossShareBP = feeSplitter.grossFeeShareBP();

        uint256 netShareAmount = (expectedNetRevenue * netShareBP) / bpScale;
        uint256 grossShareAmount = (expectedGrossRevenue * grossShareBP) / bpScale;
        uint256 feeShareAmount = netShareAmount > grossShareAmount ? netShareAmount : grossShareAmount;
        uint256 revenueRemainderRecipientShare = expectedGrossRevenue - feeShareAmount;

        // Get the default recipients from genesis setup
        address defaultRevenueShareRecipient = feeSplitter.revenueShareRecipient();
        address defaultRevenueRemainderRecipient = feeSplitter.revenueRemainderRecipient();

        // Expect the FeesDisbursed event to be emitted
        vm.expectEmit(address(Predeploys.FEE_SPLITTER));
        emit FeesDisbursed({
            revenueShareRecipient: defaultRevenueShareRecipient,
            revenueRemainderRecipient: defaultRevenueRemainderRecipient,
            revenueShareRecipientAmount: feeShareAmount,
            revenueRemainderRecipientAmount: revenueRemainderRecipientShare
        });

        // Store initial balances
        uint256 revenueShareRecipientBalanceBefore = address(defaultRevenueShareRecipient).balance;
        uint256 revenueRemainderRecipientBalanceBefore = address(defaultRevenueRemainderRecipient).balance;

        // Call disburseFees
        feeSplitter.disburseFees();

        // Verify the last disbursement time was updated
        assertEq(feeSplitter.lastDisbursementTime(), block.timestamp);

        // Verify fee recipient A received the correct amount
        assertEq(address(defaultRevenueShareRecipient).balance, revenueShareRecipientBalanceBefore + feeShareAmount);

        // Verify fee recipient B received the correct amount
        assertEq(
            address(defaultRevenueRemainderRecipient).balance,
            revenueRemainderRecipientBalanceBefore + revenueRemainderRecipientShare
        );

        // Verify the net fee revenue was reset
        assertEq(feeSplitter.netFeeRevenue(), 0);

        // Verify the FeeSplitter has no balance
        assertEq(address(Predeploys.FEE_SPLITTER).balance, 0);
    }

    /// @notice assert the setRevenueShareRecipient function reverts when the caller is not the owner
    function test_feeSplitterSetRevenueShareRecipient_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        feeSplitter.setRevenueShareRecipient(address(0x123));
    }

    /// @notice assert the setRevenueShareRecipient function reverts when the new configured share recipient is
    /// address(0)
    function test_feeSplitterSetRevenueShareRecipient_WhenInvalidNewRevenueShareRecipient_Reverts() public {
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewRevenueShareRecipientCannotBeZero.selector);
        feeSplitter.setRevenueShareRecipient(address(0));
    }

    /// @notice assert the setRevenueShareRecipient function works as expected
    function test_feeSplitterSetRevenueShareRecipient_WhenValidNewRevenueShareRecipient_Succeeds(
        address _newRevenueShareRecipient
    )
        public
    {
        vm.assume(_newRevenueShareRecipient != address(0));

        vm.prank(_owner);
        feeSplitter.setRevenueShareRecipient(_newRevenueShareRecipient);

        assertEq(feeSplitter.revenueShareRecipient(), _newRevenueShareRecipient);
    }

    /// @notice assert the setRevenueRemainderRecipient function reverts when the caller is not the owner
    function test_feeSplitterSetRevenueRemainderRecipient_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        feeSplitter.setRevenueRemainderRecipient(payable(address(0x789)));
    }

    /// @notice assert the setRevenueRemainderRecipient function reverts when the new remainder recipient is address(0)
    function test_feeSplitterSetRevenueRemainderRecipient_WhenInvalidNewRevenueRemainderRecipient_Reverts() public {
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewRevenueRemainderRecipientCannotBeZero.selector);
        feeSplitter.setRevenueRemainderRecipient(payable(address(0)));
    }

    /// @notice assert the setRevenueRemainderRecipient function works as expected
    function test_feeSplitterSetRevenueRemainderRecipient_WhenValidNewRevenueRemainderRecipient_Succeeds(
        address _newRevenueRemainderRecipient
    )
        public
    {
        vm.assume(_newRevenueRemainderRecipient != address(0));

        vm.prank(_owner);
        feeSplitter.setRevenueRemainderRecipient(payable(_newRevenueRemainderRecipient));

        assertEq(feeSplitter.revenueRemainderRecipient(), _newRevenueRemainderRecipient);
    }

    /// @notice assert the setFeeShareBP function reverts when the caller is not the owner
    function test_feeSplitterSetNetFeeShareBP_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        feeSplitter.setNetFeeShareBP(150);
    }

    /// @notice assert the setFeeShareBP function reverts when the new fee share bp is greater than 100%
    function test_feeSplitterSetNetFeeShareBP_WhenInvalidNewNetFeeShareBP_Reverts(uint16 _newNetFeeShareBP) public {
        _newNetFeeShareBP = uint16(bound(_newNetFeeShareBP, 10001, type(uint16).max));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeShareBPExceeds100Percent.selector);
        feeSplitter.setNetFeeShareBP(_newNetFeeShareBP);
    }

    /// @notice assert the setFeeShareBP function works as expected
    function test_feeSplitterSetNetFeeShareBP_WhenValidNewNetFeeShareBP_Succeeds(uint16 _newNetFeeShareBP) public {
        _newNetFeeShareBP = uint16(bound(_newNetFeeShareBP, 0, 10000));

        vm.prank(_owner);
        feeSplitter.setNetFeeShareBP(_newNetFeeShareBP);

        assertEq(feeSplitter.netFeeShareBP(), _newNetFeeShareBP);
    }

    /// @notice assert the setGrossFeeShareBP function reverts when the caller is not the owner
    function test_feeSplitterSetGrossFeeShareBP_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        feeSplitter.setGrossFeeShareBP(100);
    }

    /// @notice assert the setGrossFeeShareBP function reverts when the new gross fee share bp is greater than 100%
    function test_feeSplitterSetGrossFeeShareBP_WhenInvalid_Reverts(uint16 _newGrossFeeShareBP) public {
        _newGrossFeeShareBP = uint16(bound(_newGrossFeeShareBP, 10001, type(uint16).max));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_GrossFeeShareBPExceeds100Percent.selector);
        feeSplitter.setGrossFeeShareBP(_newGrossFeeShareBP);
    }

    /// @notice assert the setGrossFeeShareBP function works as expected
    function test_feeSplitterSetGrossFeeShareBP_WhenValid_Succeeds(uint16 _newGrossFeeShareBP) public {
        _newGrossFeeShareBP = uint16(bound(_newGrossFeeShareBP, 0, 10000));

        vm.prank(_owner);
        feeSplitter.setGrossFeeShareBP(_newGrossFeeShareBP);

        assertEq(feeSplitter.grossFeeShareBP(), _newGrossFeeShareBP);
    }

    /// @notice assert the setFeeDisbursementInterval function reverts when the caller is not the owner
    function test_feeSplitterSetFeeDisbursementInterval_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        feeSplitter.setFeeDisbursementInterval(48 hours);
    }

    /// @notice assert the setFeeDisbursementInterval function reverts when the new fee disbursement interval is less
    /// than 24 hours
    function test_feeSplitterSetFeeDisbursementInterval_WhenInvalidNewFeeDisbursementInterval_Reverts(
        uint40 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = uint40(bound(_newFeeDisbursementInterval, 0, 24 hours - 1));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewFeeDisbursementIntervalTooShort.selector);
        feeSplitter.setFeeDisbursementInterval(_newFeeDisbursementInterval);
    }

    /// @notice assert the setFeeDisbursementInterval function works as expected
    function test_feeSplitterSetFeeDisbursementInterval_WhenValidNewFeeDisbursementInterval_Succeeds(
        uint40 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = uint40(bound(_newFeeDisbursementInterval, 24 hours, type(uint40).max));

        vm.prank(_owner);
        feeSplitter.setFeeDisbursementInterval(_newFeeDisbursementInterval);

        assertEq(feeSplitter.feeDisbursementInterval(), _newFeeDisbursementInterval);
    }
}

contract Mock_FeeSplitter is FeeSplitter {
    constructor() FeeSplitter() { }

    function setPayoutGateState(uint256 _state) external {
        payoutGateState = _state;
    }
}

contract Mock_FeeVault {
    uint256 public immutable MIN_WITHDRAWAL_AMOUNT;
    address public immutable RECIPIENT;
    Types.WithdrawalNetwork public immutable WITHDRAWAL_NETWORK;
    uint256 public totalProcessed;

    event Withdrawal(uint256 value, address to, address from);
    event Withdrawal(uint256 value, address to, address from, Types.WithdrawalNetwork withdrawalNetwork);

    constructor(address payable _recipient, uint256 _minWithdrawalAmount, Types.WithdrawalNetwork _withdrawalNetwork) {
        RECIPIENT = _recipient;
        MIN_WITHDRAWAL_AMOUNT = _minWithdrawalAmount;
        WITHDRAWAL_NETWORK = _withdrawalNetwork;
    }

    receive() external payable { }

    function withdraw() external {
        require(
            address(this).balance >= MIN_WITHDRAWAL_AMOUNT,
            "FeeVault: withdrawal amount must be greater than minimum withdrawal amount"
        );

        uint256 value = address(this).balance;
        totalProcessed += value;

        emit Withdrawal(value, RECIPIENT, msg.sender);
        emit Withdrawal(value, RECIPIENT, msg.sender, WITHDRAWAL_NETWORK);

        if (WITHDRAWAL_NETWORK == Types.WithdrawalNetwork.L2) {
            (bool success,) = RECIPIENT.call{ value: value }("");
            require(success, "FeeVault: failed to send ETH to L2 fee recipient");
        }
    }
}
