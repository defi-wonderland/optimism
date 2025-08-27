// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import { L1Withdrawer } from "src/L2/L1Withdrawer.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract MockL2ToL1MessagePasser {
    receive() external payable { }

    function initiateWithdrawal(address _target, uint256 _gasLimit, bytes memory _data) external payable {
        // Mock implementation - just accept the call and ETH
    }
}

/// @title L1Withdrawer_Init
/// @notice Tests the initialization and constructor of L1Withdrawer contract.
contract L1Withdrawer_Init is Test {
    L1Withdrawer l1Withdrawer;

    function testFuzz_constructor_succeeds(uint256 _minWithdrawalAmount, address _recipient) external {
        l1Withdrawer = new L1Withdrawer(_minWithdrawalAmount, _recipient);

        assertEq(l1Withdrawer.MIN_WITHDRAWAL_AMOUNT(), _minWithdrawalAmount);
        assertEq(l1Withdrawer.RECIPIENT(), _recipient);
    }
}

/// @title L1Withdrawer_Receive_Test
/// @notice Tests the successful receive and withdrawal functionality of L1Withdrawer.
contract L1Withdrawer_Receive_Test is Test {
    L1Withdrawer l1Withdrawer;

    address recipient = makeAddr("recipient");
    uint256 minWithdrawalAmount = 1 ether;

    event WithdrawalInitiated(uint256 amount, address indexed recipient);
    event MessagePassed(
        uint256 indexed nonce,
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 gasLimit,
        bytes data,
        bytes32 withdrawalHash
    );

    function setUp() public {
        l1Withdrawer = new L1Withdrawer(minWithdrawalAmount, recipient);

        // Deploy mock at predeploy address
        vm.etch(Predeploys.L2_TO_L1_MESSAGE_PASSER, address(new MockL2ToL1MessagePasser()).code);
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
}