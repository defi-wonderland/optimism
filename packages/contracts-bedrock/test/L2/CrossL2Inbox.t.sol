// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contracts
import { CrossL2Inbox, Identifier, NoExecutingDeposits, NotWarm } from "src/L2/CrossL2Inbox.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";

/// @title CrossL2InboxWithSlotWarming
/// @dev CrossL2Inbox contract with a method to warm a slot.
contract CrossL2InboxWithSlotWarming is CrossL2Inbox {
    function warmSlot(bytes32 _slot) external view returns (uint256 res) {
        assembly {
            res := sload(_slot)
        }
    }
}

/// @title CrossL2InboxTest
/// @dev Contract for testing the CrossL2Inbox contract.
contract CrossL2InboxTest is Test {
    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    /// @dev CrossL2Inbox contract instance.
    CrossL2InboxWithSlotWarming crossL2Inbox;

    /// @dev Sets up the test suite.
    function setUp() public virtual {
        // TODO: use common test
        // super.setUp();
        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2InboxWithSlotWarming()).code);
        crossL2Inbox = CrossL2InboxWithSlotWarming(Predeploys.CROSS_L2_INBOX);
    }

    /// Test that `validateMessage` succeeds when the slot is warm.
    function testFuzz_validateMessage_accessList_succeeds(Identifier calldata _id, bytes32 _messageHash) external {
        bytes32 slot = crossL2Inbox.calculateChecksum(_id, _messageHash);
        crossL2Inbox.warmSlot(slot);

        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    /// Test that `validateMessage` reverts when the slot is not warm.
    function testFuzz_validateMessage_accessList_reverts(Identifier calldata _id, bytes32 _messageHash) external {
        bytes32 slot = keccak256(abi.encode(_id, _messageHash));

        crossL2Inbox.warmSlot(keccak256(abi.encode(slot)));

        vm.expectRevert(NotWarm.selector);
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    // TODO: Add some fuzzed test for this.
    /// Test that `calculateChecksum` succeeds matching the expected calculated checksum.
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
}
