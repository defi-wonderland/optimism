// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { IL1Withdrawer } from "interfaces/L2/IL1Withdrawer.sol";

/// @title L1Withdrawer_Test
/// @notice Tests all functionality of L1Withdrawer including receive, withdrawal, and setters.
contract L1Withdrawer_Test is CommonTest {
    address l1Withdrawer;
    IL1Withdrawer l1WithdrawerInterface;

    address recipient = makeAddr("recipient");
    uint256 minWithdrawalAmount = 1 ether;
    uint256 withdrawalGasLimit = 150_000;
    bytes withdrawalData = hex"1234";

    event WithdrawalInitiated(address indexed recipient, uint256 amount);
    event FundsReceived(address indexed sender, uint256 amount, uint256 newBalance);
    event MinWithdrawalAmountUpdated(uint256 oldMinWithdrawalAmount, uint256 newMinWithdrawalAmount);
    event RecipientUpdated(address oldRecipient, address newRecipient);
    event WithdrawalGasLimitUpdated(uint256 oldWithdrawalGasLimit, uint256 newWithdrawalGasLimit);
    event WithdrawalDataUpdated(bytes oldWithdrawalData, bytes newWithdrawalData);

    function setUp() public override {
        super.setUp();

        l1Withdrawer = DeployUtils.create1(
            "L1Withdrawer.sol:L1Withdrawer",
            DeployUtils.encodeConstructor(
                abi.encodeCall(
                    IL1Withdrawer.__constructor__, (minWithdrawalAmount, recipient, withdrawalGasLimit, withdrawalData)
                )
            )
        );
        l1WithdrawerInterface = IL1Withdrawer(l1Withdrawer);
    }

    function testFuzz_receive_belowThreshold_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 0, minWithdrawalAmount - 1);

        vm.deal(address(this), _amount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), _amount, _amount);

        (bool success,) = address(l1Withdrawer).call{ value: _amount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, _amount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);
    }

    function testFuzz_receive_atOrAboveThreshold_succeeds(uint256 _sendAmount) external {
        _sendAmount = bound(_sendAmount, minWithdrawalAmount, type(uint256).max);

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

    function testFuzz_receive_multipleDeposits_succeeds(uint256 _firstAmount, uint256 _secondAmount) external {
        // First amount should not exceed minWithdrawalAmount (so it doesn't trigger withdrawal)
        _firstAmount = bound(_firstAmount, 0, minWithdrawalAmount - 1);

        // Second amount should ensure total reaches threshold to trigger withdrawal
        _secondAmount = bound(_secondAmount, minWithdrawalAmount - _firstAmount, type(uint256).max - _firstAmount);

        uint256 totalAmount = _firstAmount + _secondAmount;

        // First deposit (should not trigger withdrawal)
        vm.deal(address(this), _firstAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), _firstAmount, _firstAmount);

        (bool success1,) = address(l1Withdrawer).call{ value: _firstAmount }("");
        assertTrue(success1);
        assertEq(address(l1Withdrawer).balance, _firstAmount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);

        // Second deposit (will trigger withdrawal since total >= minWithdrawalAmount)
        vm.deal(address(this), _secondAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit FundsReceived(address(this), _secondAmount, totalAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalInitiated(recipient, totalAmount);

        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            totalAmount,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (recipient, withdrawalGasLimit, withdrawalData))
        );

        (bool success2,) = address(l1Withdrawer).call{ value: _secondAmount }("");
        assertTrue(success2);

        // Verify withdrawal occurred
        assertEq(address(l1Withdrawer).balance, 0);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, totalAmount);
    }

    function testFuzz_setMinWithdrawalAmount_asOwner_succeeds(uint256 _newMinWithdrawalAmount) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit MinWithdrawalAmountUpdated(minWithdrawalAmount, _newMinWithdrawalAmount);

        vm.prank(owner);
        l1WithdrawerInterface.setMinWithdrawalAmount(_newMinWithdrawalAmount);

        assertEq(l1WithdrawerInterface.minWithdrawalAmount(), _newMinWithdrawalAmount);
    }

    function testFuzz_setMinWithdrawalAmount_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        uint256 newMinWithdrawalAmount = 2 ether;

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1WithdrawerInterface.setMinWithdrawalAmount(newMinWithdrawalAmount);

        assertEq(l1WithdrawerInterface.minWithdrawalAmount(), minWithdrawalAmount);
    }

    function testFuzz_setRecipient_asOwner_succeeds(address _newRecipient) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit RecipientUpdated(recipient, _newRecipient);

        vm.prank(owner);
        l1WithdrawerInterface.setRecipient(_newRecipient);

        assertEq(l1WithdrawerInterface.recipient(), _newRecipient);
    }

    function testFuzz_setRecipient_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1WithdrawerInterface.setRecipient(newRecipient);

        assertEq(l1WithdrawerInterface.recipient(), recipient);
    }

    function testFuzz_setWithdrawalGasLimit_asOwner_succeeds(uint256 _newWithdrawalGasLimit) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalGasLimitUpdated(withdrawalGasLimit, _newWithdrawalGasLimit);

        vm.prank(owner);
        l1WithdrawerInterface.setWithdrawalGasLimit(_newWithdrawalGasLimit);

        assertEq(l1WithdrawerInterface.withdrawalGasLimit(), _newWithdrawalGasLimit);
    }

    function testFuzz_setWithdrawalGasLimit_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        uint256 newWithdrawalGasLimit = 200_000;

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1WithdrawerInterface.setWithdrawalGasLimit(newWithdrawalGasLimit);

        assertEq(l1WithdrawerInterface.withdrawalGasLimit(), withdrawalGasLimit);
    }

    function testFuzz_setWithdrawalData_asOwner_succeeds(bytes memory _newWithdrawalData) external {
        address owner = proxyAdmin.owner();

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalDataUpdated(withdrawalData, _newWithdrawalData);

        vm.prank(owner);
        l1WithdrawerInterface.setWithdrawalData(_newWithdrawalData);

        assertEq(l1WithdrawerInterface.withdrawalData(), _newWithdrawalData);
    }

    function testFuzz_setWithdrawalData_asNonOwner_reverts(address _caller) external {
        address owner = proxyAdmin.owner();
        vm.assume(_caller != owner);

        bytes memory newWithdrawalData = hex"5678";

        vm.expectRevert(IL1Withdrawer.L1Withdrawer_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        l1WithdrawerInterface.setWithdrawalData(newWithdrawalData);

        assertEq(l1WithdrawerInterface.withdrawalData(), withdrawalData);
    }
}
