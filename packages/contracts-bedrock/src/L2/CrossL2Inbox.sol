// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";

// Constants
import { Constants } from "src/libraries/Constants.sol";

/// @notice Thrown when trying to execute a cross chain message on a deposit transaction.
error NoExecutingDeposits();

/// @notice Thrown when an unauthorized account attempts to force register a message.
error Unauthorized();

/// @notice The struct for a pointer to a message payload in a remote (or local) chain.
struct Identifier {
    address origin;
    uint256 blockNumber;
    uint256 logIndex;
    uint256 timestamp;
    uint256 chainId;
}
/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000022
/// @title CrossL2Inbox
/// @notice The CrossL2Inbox is responsible for executing a cross chain message on the destination
///         chain. It is permissionless to execute a cross chain message on behalf of any user.

contract CrossL2Inbox is ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.13
    string public constant version = "1.0.0-beta.13";

    /// @notice Emitted when a cross chain message is being executed.
    /// @param msgHash Hash of message payload being executed.
    /// @param id Encoded Identifier of the message.
    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    /// @notice Emitted when a cross chain message is force registered.
    /// @param msgHash Hash of message payload being force registered.
    /// @param id Encoded Identifier of the message.
    event ForceRegisteredMessage(bytes32 indexed msgHash, Identifier id);

    /// @notice Mapping of message hashes to boolean.
    /// Note that a message will only be present in this mapping if it has successfully been validated on this
    /// chain via a special L1 deposit transaction.
    mapping(bytes32 => bool) public forceRegistered;

    /// @notice Validates a cross chain message on the destination chain.
    /// @dev If called within a deposit transaction, checks if the message was force registered.
    ///      Otherwise emits an ExecutingMessage event.
    /// @param _id The identifier containing metadata about the message's origin
    /// @param _msgHash The hash of the message payload to validate
    /// @custom:throws NoExecutingDeposits If called within a deposit transaction and message is not force registered
    function validateMessage(Identifier calldata _id, bytes32 _msgHash) external {
        // We need to know if this is being called on a depositTx
        if (IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES).isDeposit()) {
            // Only if we're in a deposit, check if message is force registered
            if (!forceRegistered[keccak256(abi.encode(_msgHash, _id))]) {
                revert NoExecutingDeposits();
            }
        } else {
            emit ExecutingMessage(_msgHash, _id);
        }
    }

    /// @notice Force registers a message hash and identifier pair as validated.
    /// @dev This function can only be called by the DEPOSITOR_ACCOUNT (0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001).
    ///      Force registered messages will skip the ExecutingMessage event emission in validateMessage().
    /// @param _msgHash The hash of the message payload to register
    /// @param _id The identifier containing metadata about the message's origin
    /// @custom:security-note This is a privileged function that allows bypassing normal message validation
    function forceRegisterMessage(bytes32 _msgHash, Identifier calldata _id) external {
        // Only the depositor account can force register messages
        if (msg.sender != Constants.DEPOSITOR_ACCOUNT) revert Unauthorized();

        // Store the hash of the message+identifier as registered
        bytes32 key = keccak256(abi.encode(_msgHash, _id));
        forceRegistered[key] = true;

        // Emit the ForceRegisteredMessage event
        emit ForceRegisteredMessage(_msgHash, _id);
    }
}
