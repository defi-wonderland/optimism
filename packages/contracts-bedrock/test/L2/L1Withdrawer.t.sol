// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IL1Withdrawer } from "interfaces/L2/IL1Withdrawer.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @title L1Withdrawer_Test
/// @notice Tests all functionality of L1Withdrawer including receive, withdrawal, and setters.
contract L1Withdrawer_Test is CommonTest {
    // Test-specific parameters (the actual L1Withdrawer from genesis has different values)
    address recipient = Constants.OP_FEES_MULTISIG;
    uint216 minWithdrawalAmount = 10 ether;
    uint40 withdrawalGasLimit = 300_000;
    bytes withdrawalData = abi.encodeCall(IL1StandardBridge.depositETHTo, (Constants.OP_FEES_MULTISIG, 200_000, ""));

    event WithdrawalInitiated(address indexed recipient, uint256 amount);
    event FundsReceived(address indexed sender, uint256 amount, uint256 newBalance);
    event MinWithdrawalAmountUpdated(uint216 oldMinWithdrawalAmount, uint216 newMinWithdrawalAmount);
    event RecipientUpdated(address oldRecipient, address newRecipient);
    event WithdrawalGasLimitUpdated(uint40 oldWithdrawalGasLimit, uint40 newWithdrawalGasLimit);
    event WithdrawalDataUpdated(bytes oldWithdrawalData, bytes newWithdrawalData);

    function setUp() public override {
        // Enable revenue sharing before calling parent setUp
        super.enableRevenueShare();
        super.setUp();
    }

    function testFuzz_receive_belowThreshold_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 0, uint216(minWithdrawalAmount) - 1);

        vm.deal(address(this), _amount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), _amount, _amount);

        (bool success,) = address(l1Withdrawer).call{ value: _amount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, _amount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);
    }

    function testFuzz_receive_atOrAboveThreshold_succeeds(uint256 _sendAmount) external {
        _sendAmount = bound(_sendAmount, minWithdrawalAmount, type(uint216).max);

        vm.deal(address(this), _sendAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), _sendAmount, _sendAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalInitiated(recipient, _sendAmount);

        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            _sendAmount,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (recipient, withdrawalGasLimit, withdrawalData))
        );

        (bool success,) = address(l1Withdrawer).call{ value: _sendAmount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, 0);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, _sendAmount);
    }

    function testFuzz_receive_multipleDeposits_succeeds(uint216 _firstAmount, uint216 _secondAmount) external {
        // First amount should not exceed minWithdrawalAmount (so it doesn't trigger withdrawal)
        uint216 firstAmount = uint216(bound(_firstAmount, 0, uint216(minWithdrawalAmount) - 1));

        // Second amount should ensure total reaches threshold to trigger withdrawal
        uint216 secondAmount = uint216(bound(_secondAmount, uint216(minWithdrawalAmount) - firstAmount, type(uint216).max - firstAmount));

        uint216 totalAmount = firstAmount + secondAmount;

        // First deposit (should not trigger withdrawal)
        vm.deal(address(this), firstAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), firstAmount, firstAmount);

        (bool success1,) = address(l1Withdrawer).call{ value: firstAmount }("");
        assertTrue(success1);
        assertEq(address(l1Withdrawer).balance, firstAmount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);

        // Second deposit (will trigger withdrawal since total >= minWithdrawalAmount)
        vm.deal(address(this), secondAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), secondAmount, totalAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalInitiated(recipient, totalAmount);

        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            totalAmount,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (recipient, withdrawalGasLimit, withdrawalData))
        );

        (bool success2,) = address(l1Withdrawer).call{ value: secondAmount }("");
        assertTrue(success2);

        // Verify withdrawal occurred
        assertEq(address(l1Withdrawer).balance, 0);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, totalAmount);
    }

    function testFuzz_setMinWithdrawalAmount_asOwner_succeeds(uint216 _newMinWithdrawalAmount) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit MinWithdrawalAmountUpdated(l1Withdrawer.minWithdrawalAmount(), _newMinWithdrawalAmount);

        vm.prank(owner);
        l1Withdrawer.setMinWithdrawalAmount(_newMinWithdrawalAmount);

        assertEq(l1Withdrawer.minWithdrawalAmount(), _newMinWithdrawalAmount);
    }

    function testFuzz_setMinWithdrawalAmount_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        uint216 newMinWithdrawalAmount = 2 ether;

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1Withdrawer.setMinWithdrawalAmount(newMinWithdrawalAmount);

        uint216 currentMinWithdrawalAmount = l1Withdrawer.minWithdrawalAmount();
        assertEq(l1Withdrawer.minWithdrawalAmount(), currentMinWithdrawalAmount);
    }

    function testFuzz_setRecipient_asOwner_succeeds(address _newRecipient) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit RecipientUpdated(recipient, _newRecipient);

        vm.prank(owner);
        l1Withdrawer.setRecipient(_newRecipient);

        assertEq(l1Withdrawer.recipient(), _newRecipient);
    }

    function testFuzz_setRecipient_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1Withdrawer.setRecipient(newRecipient);

        assertEq(l1Withdrawer.recipient(), recipient);
    }

    function testFuzz_setWithdrawalGasLimit_asOwner_succeeds(uint40 _newWithdrawalGasLimit) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalGasLimitUpdated(l1Withdrawer.withdrawalGasLimit(), _newWithdrawalGasLimit);

        vm.prank(owner);
        l1Withdrawer.setWithdrawalGasLimit(_newWithdrawalGasLimit);

        assertEq(l1Withdrawer.withdrawalGasLimit(), _newWithdrawalGasLimit);
    }

    function testFuzz_setWithdrawalGasLimit_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        uint40 newWithdrawalGasLimit = 200_000;

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1Withdrawer.setWithdrawalGasLimit(newWithdrawalGasLimit);

        uint40 currentWithdrawalGasLimit = l1Withdrawer.withdrawalGasLimit();
        assertEq(l1Withdrawer.withdrawalGasLimit(), currentWithdrawalGasLimit);
    }

    function testFuzz_setWithdrawalData_asOwner_succeeds(bytes memory _newWithdrawalData) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalDataUpdated(withdrawalData, _newWithdrawalData);

        vm.prank(owner);
        l1Withdrawer.setWithdrawalData(_newWithdrawalData);

        assertEq(l1Withdrawer.withdrawalData(), _newWithdrawalData);
    }

    function testFuzz_setWithdrawalData_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        bytes memory newWithdrawalData = hex"5678";

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1Withdrawer.setWithdrawalData(newWithdrawalData);

        assertEq(l1Withdrawer.withdrawalData(), withdrawalData);
    }
}
