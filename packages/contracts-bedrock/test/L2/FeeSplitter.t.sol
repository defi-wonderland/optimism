// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { FeeSplitter } from "src/L2/FeeSplitter.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

contract FeeSplitterTest is CommonTest {
    address private _feeRecipientA;
    address private _feeRecipientB;
    address private _owner;

    // Events
    event FeesDisbursed(
        uint256 indexed disbursementTime, uint256 paidToRecipientA, uint256 paidToRecipientB, uint256 totalFeesDisbursed
    );

    event NoFeesCollected();

    // Use common test to setup the test environment
    // Need to set up / deploy the fee splitter as a predeploy behind a proxy contract
    function setUp() public override {
        super.setUp();
        _deployFeeSplitter();
    }

    function _deployFeeSplitter() internal {
        // Deploy FeeSplitter implementation
        FeeSplitter implementation = new FeeSplitter();

        // Deploy proxy at the predeploy address with the implementation
        vm.etch(Predeploys.FEE_ROUTER, address(new Proxy(address(implementation))).code);

        // Set the admin to the ProxyAdmin predeploy
        EIP1967Helper.setAdmin(Predeploys.FEE_ROUTER, Predeploys.PROXY_ADMIN);

        // Set the implementation
        EIP1967Helper.setImplementation(Predeploys.FEE_ROUTER, address(implementation));

        // Label the contract for better debugging
        vm.label(Predeploys.FEE_ROUTER, "FeeSplitter");

        _owner = ProxyAdmin(Predeploys.PROXY_ADMIN).owner();

        // Deploy fee recipient A
        _feeRecipientA = address(new Mock_FeeRecipientA());

        // Deploy fee recipient B
        _feeRecipientB = address(new Mock_FeeRecipientB());
    }

    function _initializeFeeSplitter() internal {
        // Initialize the fee splitter as admin
        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(_feeRecipientA), payable(_feeRecipientB), 24 hours, 150
        );
    }

    function _setupMockFeeVaults() internal {
        // Deploy mock FeeVault contracts with proper configuration
        Mock_FeeVault sequencerFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault baseFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault l1FeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault operatorFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        // Etch the mock vaults at the predeploy addresses
        vm.etch(Predeploys.SEQUENCER_FEE_WALLET, address(sequencerFeeVault).code);
        vm.etch(Predeploys.BASE_FEE_VAULT, address(baseFeeVault).code);
        vm.etch(Predeploys.L1_FEE_VAULT, address(l1FeeVault).code);
        vm.etch(Predeploys.OPERATOR_FEE_VAULT, address(operatorFeeVault).code);
    }

    // assert the version is correctly set
    function test_constructor_succeeds() public {
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).version(), "1.0.0");
    }

    // assert all addresses, fee disbursement interval, and fee share are correctly set
    function test_feeSplitter_initialization() public {
        _initializeFeeSplitter();

        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).version(), "1.0.0");
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeRecipientA(), _feeRecipientA);
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeRecipientB(), _feeRecipientB);
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeDisbursementInterval(), 24 hours);
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeShareBP(), 150);
    }

    function test_feeSplitter_disburseFees_reverts_when_feeDisbursementInterval_not_reached() public {
        _initializeFeeSplitter();
        vm.roll(block.timestamp + 24 hours + 1);

        vm.expectRevert(FeeSplitter.FeeSplitter_DisbursementIntervalNotReached.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).disburseFees();
    }

    function test_feeSplitter_disburseFees_succeeds() public {
        _initializeFeeSplitter();
        _setupMockFeeVaults();

        // Add balances to the fee vaults
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 2 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 3 ether);
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 1 ether);

        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Calculate expected amounts
        uint256 totalFees = 7 ether;
        uint256 feeShareAmount = totalFees * FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeShareBP()
            / FeeSplitter(payable(Predeploys.FEE_ROUTER)).BASIS_POINT_SCALE(); // 1.5%
        uint256 feeRecipientBShare = totalFees - feeShareAmount;

        // Expect the FeesDisbursed event to be emitted
        vm.expectEmit(address(Predeploys.FEE_ROUTER));
        emit FeesDisbursed({
            disbursementTime: block.timestamp,
            paidToRecipientA: feeShareAmount,
            paidToRecipientB: feeRecipientBShare,
            totalFeesDisbursed: totalFees
        });

        // Store initial balances
        uint256 feeRecipientABalanceBefore = address(_feeRecipientA).balance;
        uint256 feeRecipientBBalanceBefore = address(_feeRecipientB).balance;

        // Call disburseFees
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).disburseFees();

        // Verify the last disbursement time was updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).lastDisbursementTime(), block.timestamp);

        // Verify fee recipient A received the correct amount
        assertEq(address(_feeRecipientA).balance, feeRecipientABalanceBefore + feeShareAmount);

        // Verify fee recipient B received the correct amount
        assertEq(address(_feeRecipientB).balance, feeRecipientBBalanceBefore + feeRecipientBShare);
    }

    function test_feeSplitter_disburseFees_noFeesCollected_succeeds() public {
        _initializeFeeSplitter();
        _setupMockFeeVaults();

        // Don't add any balances to the fee vaults
        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Expect the NoFeesCollected event to be emitted
        vm.expectEmit(address(Predeploys.FEE_ROUTER));
        emit NoFeesCollected();

        // Call disburseFees
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).disburseFees();

        // Verify the last disbursement time was NOT updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).lastDisbursementTime(), 0);
    }

    // expect a revert when initializing with an invalid _feeRecipientA (address(0))
    function test_feeSplitter_initialize_reverts_with_invalid_feeRecipientA() public {
        _deployFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeRecipientACannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(0)), payable(_feeRecipientB), 24 hours, 150
        );
    }

    // expect a revert when initializing with an invalid _feeRecipientB (address(0))
    function test_feeSplitter_initialize_reverts_with_invalid_feeRecipientB() public {
        _deployFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeRecipientBCannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).initialize(payable(_feeRecipientA), payable(address(0)), 24 hours, 150);
    }

    // expect a revert when initializing with an invalid _feeDisbursementInterval (less than 24 hours)
    function test_feeSplitter_initialize_reverts_with_invalid_feeDisbursementInterval() public {
        _deployFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeDisbursementIntervalTooShort.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(_feeRecipientA), payable(_feeRecipientB), 1 hours, 150
        );
    }

    // expect a revert when initializing with an invalid _feeShareBP (greater than 100%)
    function test_feeSplitter_initialize_reverts_with_invalid_feeShareBP() public {
        _deployFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeShareBPExceeds100Percent.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(_feeRecipientA), payable(_feeRecipientB), 24 hours, 10001
        );
    }

    // test the setFeeRecipientA function works as expected
    function test_feeSplitter_setFeeRecipientA_succeeds(address _newFeeRecipientA) public {
        vm.assume(_newFeeRecipientA != address(0));
        _initializeFeeSplitter();

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientA(_newFeeRecipientA);

        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeRecipientA(), _newFeeRecipientA);
    }

    // test the setFeeRecipientA function reverts with an invalid _newFeeRecipientA (address(0))
    function test_feeSplitter_setFeeRecipientA_reverts_with_invalid_newFeeRecipientA() public {
        _initializeFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewFeeRecipientACannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientA(address(0));
    }

    // test the setFeeRecipientA function reverts when the caller is not the owner
    function test_feeSplitter_setFeeRecipientA_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeSplitter();

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientA(address(0x123));
    }

    // test the setFeeRecipientB function works as expected
    function test_feeSplitter_setFeeRecipientB_succeeds(address _newFeeRecipientB) public {
        vm.assume(_newFeeRecipientB != address(0));
        _initializeFeeSplitter();

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientB(payable(_newFeeRecipientB));

        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeRecipientB(), _newFeeRecipientB);
    }

    // test the setFeeRecipientB function reverts with an invalid _newFeeRecipientB (address(0))
    function test_feeSplitter_setFeeRecipientB_reverts_with_invalid_newFeeRecipientB() public {
        _initializeFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewFeeRecipientBCannotBeZero.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientB(payable(address(0)));
    }

    // test the setFeeRecipientB function reverts when the caller is not the owner
    function test_feeSplitter_setFeeRecipientB_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeSplitter();

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeRecipientB(payable(address(0x789)));
    }

    // test the setFeeShareBP function works as expected
    function test_feeSplitter_setFeeShareBP_succeeds(uint256 _newFeeShareBP) public {
        _newFeeShareBP = bound(_newFeeShareBP, 0, 10000);
        _initializeFeeSplitter();

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeShareBP(_newFeeShareBP);

        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeShareBP(), _newFeeShareBP);
    }

    // test the setFeeShareBP function reverts with an invalid _newFeeShareBP (greater than 100%)
    function test_feeSplitter_setFeeShareBP_reverts_with_invalid_newFeeShareBP(uint256 _newFeeShareBP) public {
        _newFeeShareBP = bound(_newFeeShareBP, 10001, type(uint256).max);
        _initializeFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_FeeShareBPExceeds100Percent.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeShareBP(_newFeeShareBP);
    }

    // test the setFeeShareBP function reverts when the caller is not the owner
    function test_feeSplitter_setFeeShareBP_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeSplitter();

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeShareBP(150);
    }

    // test the setFeeDisbursementInterval function works as expected
    function test_feeSplitter_setFeeDisbursementInterval_succeeds(uint256 _newFeeDisbursementInterval) public {
        _newFeeDisbursementInterval = bound(_newFeeDisbursementInterval, 24 hours, type(uint256).max);
        _initializeFeeSplitter();

        vm.prank(_owner);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);

        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).feeDisbursementInterval(), _newFeeDisbursementInterval);
    }

    // test the setFeeDisbursementInterval function reverts with an invalid _newFeeDisbursementInterval (less than 24
    // hours)
    function test_feeSplitter_setFeeDisbursementInterval_reverts_with_invalid_newFeeDisbursementInterval(
        uint256 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = bound(_newFeeDisbursementInterval, 0, 24 hours - 1);
        _initializeFeeSplitter();

        vm.prank(_owner);
        vm.expectRevert(FeeSplitter.FeeSplitter_NewFeeDisbursementIntervalTooShort.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);
    }

    // test the setFeeDisbursementInterval function reverts when the caller is not the owner
    function test_feeSplitter_setFeeDisbursementInterval_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeSplitter();

        vm.prank(_caller);
        vm.expectRevert(FeeSplitter.FeeSplitter_OnlyProxyAdminOwner.selector);
        FeeSplitter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(48 hours);
    }

    // test the receive function works as expected
    function test_feeSplitter_receive_succeeds() public {
        _initializeFeeSplitter();

        // Send ETH to the FeeSplitter from a FeeVault
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 1 ether);
        vm.prank(Predeploys.SEQUENCER_FEE_WALLET);
        (bool success,) = payable(Predeploys.FEE_ROUTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was updated
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).netFeeRevenue(), 1 ether);
    }

    // test the receive function from non-FeeVault address
    function test_feeSplitter_receive_from_nonFeeVault_succeeds() public {
        _initializeFeeSplitter();

        // Send ETH to the FeeSplitter from a non-FeeVault address
        vm.deal(address(0x123), 1 ether);
        vm.prank(address(0x123));
        (bool success,) = payable(Predeploys.FEE_ROUTER).call{ value: 1 ether }("");
        assertTrue(success);

        // Verify the net fee revenue was NOT updated (only FeeVaults update it)
        assertEq(FeeSplitter(payable(Predeploys.FEE_ROUTER)).netFeeRevenue(), 0);
    }
}

contract Mock_FeeRecipientA {
    receive() external payable { }
}

contract Mock_FeeRecipientB {
    receive() external payable { }
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
