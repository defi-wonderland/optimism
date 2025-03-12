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

/// @title CrossL2InboxWithModifiableTransientStorage
/// @dev CrossL2Inbox contract with methods to modify the transient storage.
///      This is used to test the transient storage of CrossL2Inbox.
contract CrossL2InboxWithModifiableTransientStorage is CrossL2Inbox {
    function warmSlot(bytes32 _slot) external view returns (uint256 res) {
        assembly {
            res := sload(_slot)
        }
    }
}

/// @title CrossL2InboxTest
/// @dev Contract for testing the CrossL2Inbox contract.
contract CrossL2InboxTest is Test {
    string public constant MNEMONIC = "test test test test test test test test test test test junk"; // L2 dev accounts
    uint256 public immutable PRIVATE_KEY = vm.deriveKey(MNEMONIC, 0);
    address public immutable DEPLOYER = vm.rememberKey(PRIVATE_KEY);

    /// @dev Selector for the `isInDependencySet` method of the L1Block contract.
    bytes4 constant L1BlockIsInDependencySetSelector = bytes4(keccak256("isInDependencySet(uint256)"));

    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    /// @dev CrossL2Inbox contract instance.
    CrossL2InboxWithModifiableTransientStorage crossL2Inbox;

    /// @dev Sets up the test suite.
    function setUp() public virtual {
        // TODO: use common test
        // super.setUp();
        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2InboxWithModifiableTransientStorage()).code);
        crossL2Inbox = CrossL2InboxWithModifiableTransientStorage(Predeploys.CROSS_L2_INBOX);
    }

    /// Tests that validateMessage succeeds for a non-deposit transaction.
    function testFuzz_validateMessage_succeeds(Identifier memory _id, bytes32 _messageHash) external {
        // Ensure is not a deposit transaction
        vm.mockCall({
            callee: Predeploys.L1_BLOCK_ATTRIBUTES,
            data: abi.encodeCall(IL1BlockInterop.isDeposit, ()),
            returnData: abi.encode(false)
        });

        // Look for the emit ExecutingMessage event
        vm.expectEmit(Predeploys.CROSS_L2_INBOX);
        emit ExecutingMessage(_messageHash, _id);

        // Call the validateMessage function
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    /// Tests that validateMessage reverts for a deposit transaction.
    function testFuzz_validateMessage_isDeposit_reverts(Identifier calldata _id, bytes32 _messageHash) external {
        // Ensure it is a deposit transaction
        vm.mockCall({
            callee: Predeploys.L1_BLOCK_ATTRIBUTES,
            data: abi.encodeCall(IL1BlockInterop.isDeposit, ()),
            returnData: abi.encode(true)
        });

        // Expect a revert with the NoExecutingDeposits selector
        vm.expectRevert(NoExecutingDeposits.selector);

        // Call the validateMessage function
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    /// AccessList Tests
    function test_validateMessage_accessList_succeeds(Identifier calldata _id, bytes32 _messageHash) external {
        bytes32 slot = crossL2Inbox.calculateChecksum(_id, _messageHash);

        crossL2Inbox.warmSlot(slot);

        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    function test_validateMessage_accessList_reverts(Identifier calldata _id, bytes32 _messageHash) external {
        bytes32 slot = keccak256(abi.encode(_id, _messageHash));

        crossL2Inbox.warmSlot(keccak256(abi.encode(slot)));

        vm.expectRevert(NotWarm.selector);
        crossL2Inbox.validateMessage(_id, _messageHash);
    }

    function test_validateMessage_checksum_proto_succeeds() external view {
        Identifier memory _id = Identifier(
            address(0),
            uint64(0xa1a2a3a4a5a6a7a8),
            uint32(0xb1b2b3b4),
            uint64(0xc1c2c3c4c5c6c7c8),
            uint256(0xd1d2d3d4d5d6d7d8)
        );

        bytes32 _messageHash = 0x8017559a85b12c04b14a1a425d53486d1015f833714a09bd62f04152a7e2ae9b;
        bytes32 _checksum = crossL2Inbox.calculateChecksum(_id, _messageHash);
        bytes32 _expectedChecksum = 0x03139ddd21106abad4bb82800fedfa3a103f53f242c2d5b7615b0baad8379531;
        assertEq(_checksum, _expectedChecksum);
    }
}
