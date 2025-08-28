// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { IL1Withdrawer } from "interfaces/L2/IL1Withdrawer.sol";

/// @title L1Withdrawer_Receive_Test
/// @notice Tests the successful receive and withdrawal functionality of L1Withdrawer.
contract L1Withdrawer_Receive_Test is CommonTest {
    address l1Withdrawer;

    address recipient = makeAddr("recipient");
    uint256 minWithdrawalAmount = 1 ether;
    uint256 withdrawalGasLimit = 150_000;
    bytes withdrawalData = hex"1234";

    event WithdrawalInitiated(uint256 amount, address indexed recipient);

    function setUp() public override {
        super.setUp();

        // Deploy L1Withdrawer using vm.etch with constructor parameters
        l1Withdrawer = makeAddr("l1Withdrawer");
        l1Withdrawer = DeployUtils.create1(
            "L1Withdrawer.sol:L1Withdrawer",
            DeployUtils.encodeConstructor(
                abi.encodeCall(
                    IL1Withdrawer.__constructor__, (minWithdrawalAmount, recipient, withdrawalGasLimit, withdrawalData)
                )
            )
        );
    }

    function testFuzz_receive_belowThreshold_succeeds(uint256 _amount) external {
        vm.assume(_amount > 0 && _amount < minWithdrawalAmount);

        vm.deal(address(this), _amount);
        (bool success,) = address(l1Withdrawer).call{ value: _amount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, _amount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);
    }

    function testFuzz_receive_atOrAboveThreshold_succeeds(uint256 _sendAmount) external {
        vm.assume(_sendAmount >= minWithdrawalAmount);
        vm.assume(_sendAmount < type(uint128).max); // Avoid overflow

        vm.deal(address(this), _sendAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalInitiated(_sendAmount, recipient);

        (bool success,) = address(l1Withdrawer).call{ value: _sendAmount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, 0);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, _sendAmount);
    }

    function testFuzz_receive_multipleDeposits_succeeds(uint256 _firstAmount, uint256 _secondAmount) external {
        // First amount should not exceed minWithdrawalAmount (so it doesn't trigger withdrawal)
        vm.assume(_firstAmount > 0 && _firstAmount < minWithdrawalAmount);

        // Second amount should ensure total reaches threshold to trigger withdrawal
        vm.assume(_secondAmount >= minWithdrawalAmount - _firstAmount);
        vm.assume(_secondAmount < type(uint128).max); // Avoid overflow

        uint256 totalAmount = _firstAmount + _secondAmount;

        // First deposit (should not trigger withdrawal)
        vm.deal(address(this), _firstAmount);
        (bool success1,) = address(l1Withdrawer).call{ value: _firstAmount }("");
        assertTrue(success1);
        assertEq(address(l1Withdrawer).balance, _firstAmount);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, 0);

        // Second deposit (will trigger withdrawal since total >= minWithdrawalAmount)
        vm.deal(address(this), _secondAmount);

        vm.expectEmit(address(l1Withdrawer));
        emit WithdrawalInitiated(totalAmount, recipient);

        (bool success2,) = address(l1Withdrawer).call{ value: _secondAmount }("");
        assertTrue(success2);

        // Verify withdrawal occurred
        assertEq(address(l1Withdrawer).balance, 0);
        assertEq(address(Predeploys.L2_TO_L1_MESSAGE_PASSER).balance, totalAmount);
    }

    function test_receive_verifyWithdrawalCall_succeeds() external {
        uint256 sendAmount = 1.5 ether;

        // Expect the specific call to initiateWithdrawal with custom parameters
        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            sendAmount,
            abi.encodeWithSelector(
                IL2ToL1MessagePasser.initiateWithdrawal.selector, recipient, withdrawalGasLimit, withdrawalData
            )
        );

        vm.deal(address(this), sendAmount);
        (bool success,) = address(l1Withdrawer).call{ value: sendAmount }("");

        assertTrue(success);
        assertEq(address(l1Withdrawer).balance, 0);
    }
}
