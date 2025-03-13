// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Constants } from "src/libraries/Constants.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";

import { console } from "forge-std/console.sol";

interface ICrossL2InboxWithSlotWarming is ICrossL2Inbox {
    function warmSlot(bytes32 _slot) external view returns (uint256 res);
    function isWarm(bytes32 _slot) external view returns (bool isWarm_, uint256 value_);
}

/// @title CrossL2InboxTest
/// @dev Contract for testing the CrossL2Inbox contract.
contract CrossL2InboxTest is CommonTest {
    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    /// @dev CrossL2Inbox contract instance.
    ICrossL2InboxWithSlotWarming crossL2Inbox;

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();

        /// NOTE: Getting mock from artifacts due to incompatibilities between compiler versions.
        ///       Reading and parsing JSON because `vm.getCode` doesn't find it in the artifacts.
        // Load the bytecode from the JSON artifact
        string memory path = "forge-artifacts/CrossL2InboxWithSlotWarming.sol/CrossL2InboxWithSlotWarming.json";
        string memory json = vm.readFile(path);

        // Apply the bytecode to the contract address
        bytes memory bytecode = vm.parseJsonBytes(json, ".deployedBytecode.object");
        vm.etch(Predeploys.CROSS_L2_INBOX, bytecode);

        crossL2Inbox = ICrossL2InboxWithSlotWarming(Predeploys.CROSS_L2_INBOX);
    }

    /// Test that `validateMessage` reverts when the slot is not warm.
    function testFuzz_validateMessage_accessList_reverts(Identifier calldata _id, bytes32 _messageHash) external {
        vm.expectRevert(ICrossL2Inbox.NotWarm.selector);
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    /// Test that `validateMessage` succeeds when the slot for the message checksum is warm.
    function testFuzz_validateMessage_succeeds(Identifier calldata _id, bytes32 _messageHash) external {
        // Warm the slot
        bytes32 slot = crossL2Inbox.calculateChecksum(_id, _messageHash);
        crossL2Inbox.warmSlot(slot);

        // Expect `ExecutingMessage` event to be emitted
        vm.expectEmit(address(crossL2Inbox));
        emit ExecutingMessage(_messageHash, _id);

        // Validate the message
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    /// Test that `calculateChecksum` succeeds matching the expected calculated checksum.
    /// Using a hardcoded checksum manually calculated and verified.
    function test_calculateChecksum_succeeds() external view {
        Identifier memory id = Identifier(
            address(0),
            uint64(0xa1a2a3a4a5a6a7a8),
            uint32(0xb1b2b3b4),
            uint64(0xc1c2c3c4c5c6c7c8),
            uint256(0xd1d2d3d4d5d6d7d8)
        );

        // Calculate the expected checksum.
        bytes32 messageHash = 0x8017559a85b12c04b14a1a425d53486d1015f833714a09bd62f04152a7e2ae9b;
        bytes32 checksum = crossL2Inbox.calculateChecksum(id, messageHash);
        bytes32 expectedChecksum = 0x03139ddd21106abad4bb82800fedfa3a103f53f242c2d5b7615b0baad8379531;

        // Expect it to match
        assertEq(checksum, expectedChecksum);
    }

    /// Test that `_isWarm` returns the correct value when the slot is not warm.
    function testFuzz_isWarm_succeeds_whenSlotIsNotWarm(bytes32 _slot) external view {
        // Avoid collisions with the proxy layout.
        vm.assume(_slot != Constants.PROXY_IMPLEMENTATION_ADDRESS);
        vm.assume(_slot != Constants.PROXY_OWNER_ADDRESS);

        // Assert that the slot is not warm
        (bool isWarm, uint256 value) = crossL2Inbox.isWarm(_slot);
        assertEq(isWarm, false);
        assertEq(value, 0);
    }

    /// Test that `_isWarm` returns the correct value when the slot is warm.
    function testFuzz_isWarm_succeeds_whenSlotIsWarm(Identifier calldata _id, bytes32 _messageHash) external view {
        bytes32 slot = crossL2Inbox.calculateChecksum(_id, _messageHash);

        // Avoid collisions with the proxy layout.
        vm.assume(slot != Constants.PROXY_IMPLEMENTATION_ADDRESS);
        vm.assume(slot != Constants.PROXY_OWNER_ADDRESS);

        // Warm the slot
        crossL2Inbox.warmSlot(slot);

        // Assert that the slot is warm
        (bool isWarm, uint256 value) = crossL2Inbox.isWarm(slot);
        assertEq(isWarm, true);
        assertEq(value, 0);
    }
}
