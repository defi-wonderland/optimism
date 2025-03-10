// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SafeSend } from "src/universal/SafeSend.sol";
import { CommonTest } from "test/setup/CommonTest.sol";

contract SafeSendTest is CommonTest {
    /// @notice Tests that sending to an EOA succeeds.
    function test_send_toEOA_succeeds() public {
        assertNotEq(alice, address(0));
        assertNotEq(bob, address(0));
        assertEq(bob.code.length, 0);

        vm.deal(alice, 100 ether);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        SafeSend safeSend = new SafeSend{ value: 100 ether }(payable(bob));

        assertEq(address(safeSend).code.length, 0);
        assertEq(address(safeSend).balance, 0);
        assertEq(alice.balance, aliceBalanceBefore - 100 ether);
        assertEq(bob.balance, bobBalanceBefore + 100 ether);
    }

    /// @notice Tests that sending to a contract succeeds without executing the
    ///         contract's code.
    function test_send_toContract_succeeds() public {
        // etch reverting code into bob
        vm.etch(bob, hex"fe");
        vm.deal(alice, 100 ether);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        SafeSend safeSend = new SafeSend{ value: 100 ether }(payable(bob));

        assertEq(address(safeSend).code.length, 0);
        assertEq(address(safeSend).balance, 0);
        assertEq(alice.balance, aliceBalanceBefore - 100 ether);
        assertEq(bob.balance, bobBalanceBefore + 100 ether);
    }

    /// @notice Tests that sending to a contract with leftover ETH succeeds.
    function test_send_toContractWithLeftoverETH_succeeds() public {
        // Deal ETH to the alice and bob addresses
        uint256 leftoverETH = 10 ether;
        uint256 safeSendValue = 100 ether;
        vm.deal(alice, leftoverETH + safeSendValue);

        // Get the SafeSend contract address to be deployed
        address safeSend = vm.computeCreateAddress(alice, vm.getNonce(alice));

        // Send some ETH to the contract address before it is deployed-- this will be the leftover ETH
        vm.startPrank(alice);
        payable(safeSend).transfer(leftoverETH);

        // Get the balances before the deployment
        uint256 zeroAddressBalanceBefore = address(0).balance;
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        // Deploy the SafeSend contract
        new SafeSend{ value: safeSendValue }(payable(bob));

        // Assert
        assertEq(address(safeSend).code.length, 0);
        assertEq(address(safeSend).balance, 0);
        assertEq(alice.balance, aliceBalanceBefore - safeSendValue);
        assertEq(bob.balance, bobBalanceBefore + safeSendValue);
        assertEq(address(0).balance, zeroAddressBalanceBefore + leftoverETH);
    }
}
