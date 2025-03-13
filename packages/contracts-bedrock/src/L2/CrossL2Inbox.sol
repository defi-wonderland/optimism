// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @notice Thrown when trying to execute a cross chain message on a deposit transaction.
error NoExecutingDeposits();

/// @notice Thrown when trying to validate a cross chain message with an identifier checksum that is
///         invalid or was not provided in the transaction's access list to set the slot as warm.
error NotWarm();

/// @notice The struct for a pointer to a message payload in a remote (or local) chain.
/// @custom:field origin The origin address of the message.
/// @custom:field blockNumber The block number of the message.
/// @custom:field logIndex The log index of the message.
/// @custom:field timestamp The timestamp of the message.
/// @custom:field chainId The origin chain ID of the message.
struct Identifier {
    address origin;
    uint64 blockNumber;
    uint32 logIndex;
    uint64 timestamp;
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

    // TODO: Check natspec
    /// @notice The mask for the most significant bits of the checksum.
    bytes32 internal constant _MSB_MASK = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice The mask for the type 3 bits of the checksum.
    bytes32 internal constant _TYPE_3_MASK = 0x0300000000000000000000000000000000000000000000000000000000000000;

    /// TODO: discuss a safe value for this
    /// @notice The threshold to use to know whether the slot is warm or not.
    uint256 internal constant _WARM_READ_THRESHOLD = 150;

    /// @notice Emitted when a cross chain message is being executed.
    /// @param msgHash Hash of message payload being executed.
    /// @param id Encoded Identifier of the message.
    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    /// @notice Validates a cross chain message on the destination chain
    ///         and emits an ExecutingMessage event. This function is useful
    ///         for applications that understand the schema of the _message payload and want to
    ///         process it in a custom way.
    /// @param _id      Identifier of the message.
    /// @param _msgHash Hash of the message payload to call target with.
    function validateMessage(Identifier calldata _id, bytes32 _msgHash) external {
        bytes32 checksum = calculateChecksum(_id, _msgHash);
        (bool isWarm,) = _isWarm(checksum);
        if (!isWarm) revert NotWarm();

        emit ExecutingMessage(_msgHash, _id);
    }

    // TODO: Needs to be public?
    /// @notice Calculates the checksum for a cross chain message.
    /// @param _id The identifier of the message.
    /// @param _msgHash The hash of the message.
    /// @return checksum_ The checksum of the message.
    function calculateChecksum(Identifier memory _id, bytes32 _msgHash) public pure returns (bytes32 checksum_) {
        bytes32 logHash = keccak256(abi.encodePacked(_id.origin, _msgHash));
        bytes32 idPacked = bytes32(abi.encodePacked(uint96(0), _id.blockNumber, _id.timestamp, _id.logIndex));
        bytes32 idLogHash = keccak256(abi.encodePacked(logHash, idPacked));

        // TODO: Add some comment
        bytes32 bareChecksum = keccak256(abi.encodePacked(idLogHash, _id.chainId));
        checksum_ = (bareChecksum & _MSB_MASK) | _TYPE_3_MASK;
    }

    /// @notice Checks if a slot is warm by measuring the gas cost of loading the slot.
    /// @dev    Stores and returns the slot value so that the compiler doesn't optimize out the
    ///         `sload`, this adds cost to the read
    /// @param _slot The slot to check.
    /// @return isWarm_ Whether the slot is warm.
    /// @return value_ The slot value.
    function _isWarm(bytes32 _slot) internal view returns (bool isWarm_, uint256 value_) {
        assembly {
            // Get the gas cost of the reading the slot with `sload`.
            let startGas := gas()
            value_ := sload(_slot)
            let endGas := gas()
            // If the gas cost of the `sload` is below than the threshold, the slot is warm.
            isWarm_ := iszero(gt(sub(startGas, endGas), _WARM_READ_THRESHOLD))
        }
    }
}
