// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contracts
import { CrossL2Inbox, Identifier, NoExecutingDeposits } from "src/L2/CrossL2Inbox.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";

/// @title CrossL2InboxTest
/// @dev Contract for testing the CrossL2Inbox contract.
contract CrossL2InboxTest is Test {
    /// @dev CrossL2Inbox contract instance.
    CrossL2Inbox crossL2Inbox;

    /// @dev Sets up the test suite.
    function setUp() public {
        // Deploy the CrossL2Inbox contract
        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2Inbox()).code);
        crossL2Inbox = CrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    }

    function testFuzz_validateMessage_succeeds(Identifier memory _id, bytes32 _messageHash) external {
        // Ensure is not a deposit transaction
        vm.mockCall({
            callee: Predeploys.L1_BLOCK_ATTRIBUTES,
            data: abi.encodeCall(IL1BlockInterop.isDeposit, ()),
            returnData: abi.encode(false)
        });

        // Look for the emit ExecutingMessage event
        vm.expectEmit(Predeploys.CROSS_L2_INBOX);
        emit CrossL2Inbox.ExecutingMessage(_messageHash, _id);

        // Call the validateMessage function
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    function testFuzz_validateMessage_isDeposit_reverts(Identifier calldata _id, bytes32 _messageHash) external {
        // Ensure it is a deposit transaction
        vm.mockCall({
            callee: Predeploys.L1_BLOCK_ATTRIBUTES,
            data: abi.encodeCall(IL1BlockInterop.isDeposit, ()),
            returnData: abi.encode(true)
        });

        // Expect a revert with the NoExecutingDeposits selector
        vm.expectRevert(NoExecutingDeposits.selector);

        // Call the executeMessage function
        crossL2Inbox.validateMessage(_id, _messageHash);
    }
}
