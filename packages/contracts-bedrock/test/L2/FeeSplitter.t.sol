// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { FeeSplitter } from "src/L2/FeeSplitter.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

contract FeeSplitterTest is CommonTest {
    address private _configuredShareRecipient;
    address private _remainderRecipient;
    address private _owner;

    // Events
    event FeesDisbursed(
        uint256 indexed disbursementTime,
        uint256 paidConfiguredShareRecipient,
        uint256 paidToRemainderRecipient,
        uint256 totalFeesDisbursed
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
        _configuredShareRecipient = makeAddr("ConfiguredShareRecipient");
        _remainderRecipient = makeAddr("RemainderRecipient");
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

    /// @notice assert the version is correctly set
    function test_constructor_succeeds() public {
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).version(), "1.0.0");
    }

    /// @notice assert all addresses, fee disbursement interval, and fee share are correctly set
    function test_feeSplitter_initialization() public {
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).version(), "1.0.0");
        assertEq(
            FeeSplitter(payable(Predeploys.FEE_SPLITTER)).configuredShareRecipient(),
            address(0x1234567890123456789012345678901234567890)
        );
        assertEq(
            FeeSplitter(payable(Predeploys.FEE_SPLITTER)).remainderRecipient(),
            address(0x0987654321098765432109876543210987654321)
        );
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).feeDisbursementInterval(), 24 hours);
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeShareBP(), 1_500);
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).grossFeeShareBP(), 250);
    }

    /// @notice assert the disburseFees function reverts when the fee disbursement interval has not been reached
    function test_feeSplitterDisburseFees_WhenFeeDisbursementIntervalNotReached_Reverts() public {
        vm.roll(block.timestamp + 24 hours + 1);

        vm.expectRevert(FeeSplitter.FeeSplitter_DisbursementIntervalNotReached.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).disburseFees();
    }

    /// @notice assert the disburseFees function succeeds when the fee disbursement interval has been reached
    function test_feeSplitterDisburseFees_succeeds() public {
        _setupMockFeeVaults();

        // Add balances to the fee vaults
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 2 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 3 ether);
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 1 ether);

        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Calculate expected amounts using max(netShare, grossShare) from contract
        uint256 expectedTotalFees = address(Predeploys.SEQUENCER_FEE_WALLET).balance
            + address(Predeploys.BASE_FEE_VAULT).balance + address(Predeploys.L1_FEE_VAULT).balance
            + address(Predeploys.OPERATOR_FEE_VAULT).balance;

        uint256 expectedNetRevenue = address(Predeploys.SEQUENCER_FEE_WALLET).balance
            + address(Predeploys.BASE_FEE_VAULT).balance + address(Predeploys.OPERATOR_FEE_VAULT).balance;

        uint256 bpScale = FeeSplitter(payable(Predeploys.FEE_SPLITTER)).BASIS_POINT_SCALE();
        uint256 netShareBP = FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeShareBP();
        uint256 grossShareBP = FeeSplitter(payable(Predeploys.FEE_SPLITTER)).grossFeeShareBP();

        uint256 netShareAmount = (expectedNetRevenue * netShareBP) / bpScale;
        uint256 grossShareAmount = (expectedTotalFees * grossShareBP) / bpScale;
        uint256 feeShareAmount = netShareAmount > grossShareAmount ? netShareAmount : grossShareAmount;
        uint256 remainderRecipientShare = expectedTotalFees - feeShareAmount;

        // Get the default recipients from genesis setup
        address defaultConfiguredShareRecipient =
            FeeSplitter(payable(Predeploys.FEE_SPLITTER)).configuredShareRecipient();
        address defaultRemainderRecipient = FeeSplitter(payable(Predeploys.FEE_SPLITTER)).remainderRecipient();

        // Expect the FeesDisbursed event to be emitted
        vm.expectEmit(address(Predeploys.FEE_SPLITTER));
        emit FeesDisbursed({
            disbursementTime: block.timestamp,
            paidConfiguredShareRecipient: feeShareAmount,
            paidToRemainderRecipient: remainderRecipientShare,
            totalFeesDisbursed: expectedTotalFees
        });

        // Store initial balances
        uint256 configuredShareRecipientBalanceBefore = address(defaultConfiguredShareRecipient).balance;
        uint256 remainderRecipientBalanceBefore = address(defaultRemainderRecipient).balance;

        // Call disburseFees
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).disburseFees();

        // Verify the last disbursement time was updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).lastDisbursementTime(), block.timestamp);

        // Verify fee recipient A received the correct amount
        assertEq(
            address(defaultConfiguredShareRecipient).balance, configuredShareRecipientBalanceBefore + feeShareAmount
        );

        // Verify fee recipient B received the correct amount
        assertEq(address(defaultRemainderRecipient).balance, remainderRecipientBalanceBefore + remainderRecipientShare);

        // Verify the net fee revenue was reset
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeRevenue(), 0);
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

        // Call disburseFees
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).disburseFees();

        // Verify the last disbursement time was NOT updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).lastDisbursementTime(), 0);
    }

    /// @notice assert the initialize function reverts when the configured share recipient is address(0)
    function test_feeSplitterInitialize_WhenInvalidConfiguredShareRecipient_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_ConfiguredShareRecipientCannotBeZero.selector);
        IFeeSplitter(payable(impl)).initialize(payable(address(0)), payable(_remainderRecipient), 24 hours, 10001, 250);
    }

    /// @notice assert the initialize function reverts when the remainder recipient is address(0)
    function test_feeSplitterInitialize_WhenInvalidRemainderRecipient_Reverts() public {
        // Deploy a fresh instance for testing initialization
        address impl = address(uint160(uint256(keccak256("FeeSplitterTestImpl2"))));
        vm.etch(impl, vm.getDeployedCode("FeeSplitter.sol:FeeSplitter"));
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_RemainderRecipientCannotBeZero.selector);
        IFeeSplitter(payable(impl)).initialize(
            payable(_configuredShareRecipient), payable(address(0)), 24 hours, 10001, 250
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
            payable(_configuredShareRecipient), payable(_remainderRecipient), 1 hours, 1_500, 250
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
            payable(_configuredShareRecipient), payable(_remainderRecipient), 24 hours, 10001, 250
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
            payable(_configuredShareRecipient), payable(_remainderRecipient), 24 hours, 1_500, 10001
        );
    }

    /// @notice assert the initialize function reverts when the contract is already initialized
    function test_feeSplitterInitialize_WhenAlreadyInitialized_Reverts() public {
        vm.expectRevert("Initializable: contract is already initialized");
        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).initialize(
            payable(_configuredShareRecipient), payable(_remainderRecipient), 24 hours, 1_500, 250
        );
    }

    /// @notice assert the setConfiguredShareRecipient function works as expected
    function test_feeSplitterSetConfiguredShareRecipient_WhenValidNewConfiguredShareRecipient_Succeeds(
        address _newConfiguredShareRecipient
    )
        public
    {
        vm.assume(_newConfiguredShareRecipient != address(0));

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setConfiguredShareRecipient(_newConfiguredShareRecipient);

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).configuredShareRecipient(), _newConfiguredShareRecipient);
    }

    /// @notice assert the setConfiguredShareRecipient function reverts when the new configured share recipient is
    /// address(0)
    function test_feeSplitterSetConfiguredShareRecipient_WhenInvalidNewConfiguredShareRecipient_Reverts() public {
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewConfiguredShareRecipientCannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setConfiguredShareRecipient(address(0));
    }

    /// @notice assert the setConfiguredShareRecipient function reverts when the caller is not the owner
    function test_feeSplitterSetConfiguredShareRecipient_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setConfiguredShareRecipient(address(0x123));
    }

    /// @notice assert the setRemainderRecipient function works as expected
    function test_feeSplitterSetRemainderRecipient_WhenValidOldRemainderRecipient_Succeeds(
        address _oldRemainderRecipient
    )
        public
    {
        vm.assume(_oldRemainderRecipient != address(0));

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setRemainderRecipient(payable(_oldRemainderRecipient));

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).remainderRecipient(), _oldRemainderRecipient);
    }

    /// @notice assert the setRemainderRecipient function reverts when the old remainder recipient is address(0)
    function test_feeSplitterSetRemainderRecipient_WhenInvalidOldRemainderRecipient_Reverts() public {
        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewRemainderRecipientCannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setRemainderRecipient(payable(address(0)));
    }

    /// @notice assert the setRemainderRecipient function reverts when the caller is not the owner
    function test_feeSplitterSetRemainderRecipient_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setRemainderRecipient(payable(address(0x789)));
    }

    /// @notice assert the setFeeShareBP function works as expected
    function test_feeSplitterSetNetFeeShareBP_WhenValidNewNetFeeShareBP_Succeeds(uint32 _newNetFeeShareBP) public {
        _newNetFeeShareBP = uint32(bound(_newNetFeeShareBP, 0, 10000));

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setNetFeeShareBP(_newNetFeeShareBP);

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeShareBP(), _newNetFeeShareBP);
    }

    /// @notice assert the setFeeShareBP function reverts when the new fee share bp is greater than 100%
    function test_feeSplitterSetNetFeeShareBP_WhenInvalidNewNetFeeShareBP_Reverts(uint32 _newNetFeeShareBP) public {
        _newNetFeeShareBP = uint32(bound(_newNetFeeShareBP, 10001, type(uint256).max));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeShareBPExceeds100Percent.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setNetFeeShareBP(_newNetFeeShareBP);
    }

    /// @notice assert the setFeeShareBP function reverts when the caller is not the owner
    function test_feeSplitterSetNetFeeShareBP_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setNetFeeShareBP(150);
    }

    /// @notice assert the setFeeDisbursementInterval function works as expected
    function test_feeSplitterSetFeeDisbursementInterval_WhenValidNewFeeDisbursementInterval_Succeeds(
        uint32 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = uint32(bound(_newFeeDisbursementInterval, 24 hours, type(uint256).max));

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).feeDisbursementInterval(), _newFeeDisbursementInterval);
    }

    /// @notice assert the setFeeDisbursementInterval function reverts when the new fee disbursement interval is less
    /// than 24 hours
    function test_feeSplitterSetFeeDisbursementInterval_WhenInvalidNewFeeDisbursementInterval_Reverts(
        uint32 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = uint32(bound(_newFeeDisbursementInterval, 0, 24 hours - 1));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewFeeDisbursementIntervalTooShort.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);
    }

    /// @notice assert the setFeeDisbursementInterval function reverts when the caller is not the owner
    function test_feeSplitterSetFeeDisbursementInterval_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setFeeDisbursementInterval(48 hours);
    }

    /// @notice assert the receive function works as expected
    function test_feeSplitterReceive_WhenValidFeeVault_Succeeds() public {
        // Send ETH to the FeeSplitter from a FeeVault
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 1 ether);
        vm.prank(Predeploys.SEQUENCER_FEE_WALLET);
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeRevenue(), 1 ether);
    }

    /// @notice assert the receive function from non-FeeVault address
    function test_feeSplitterReceive_WhenNonFeeVault_Succeeds() public {
        // Send ETH to the FeeSplitter from a non-FeeVault address
        vm.deal(address(0x123), 1 ether);
        vm.prank(address(0x123));
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was NOT updated (only FeeVaults update it)
        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeRevenue(), 0);
    }

    /// @notice assert the receive function from L1 FeeVault does not increment net revenue
    function test_feeSplitterReceive_WhenL1FeeVault_DoesNotIncrementNetRevenue() public {
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.prank(Predeploys.L1_FEE_VAULT);
        (bool success,) = payable(Predeploys.FEE_SPLITTER).call{ value: 1 ether }("");
        assertTrue(success);

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).netFeeRevenue(), 0);
    }

    /// @notice assert the setGrossFeeShareBP function works as expected
    function test_feeSplitterSetGrossFeeShareBP_WhenValid_Succeeds(uint32 _newGrossFeeShareBP) public {
        _newGrossFeeShareBP = uint32(bound(_newGrossFeeShareBP, 0, 10000));

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setGrossFeeShareBP(_newGrossFeeShareBP);

        assertEq(FeeSplitter(payable(Predeploys.FEE_SPLITTER)).grossFeeShareBP(), _newGrossFeeShareBP);
    }

    /// @notice assert the setGrossFeeShareBP function reverts when the new gross fee share bp is greater than 100%
    function test_feeSplitterSetGrossFeeShareBP_WhenInvalid_Reverts(uint32 _newGrossFeeShareBP) public {
        _newGrossFeeShareBP = uint32(bound(_newGrossFeeShareBP, 10001, type(uint256).max));

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_GrossFeeShareBPExceeds100Percent.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setGrossFeeShareBP(_newGrossFeeShareBP);
    }

    /// @notice assert the setGrossFeeShareBP function reverts when the caller is not the owner
    function test_feeSplitterSetGrossFeeShareBP_WhenCallerIsNotOwner_Reverts(address _caller) public {
        vm.assume(_caller != _owner);

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_SPLITTER)).setGrossFeeShareBP(100);
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
