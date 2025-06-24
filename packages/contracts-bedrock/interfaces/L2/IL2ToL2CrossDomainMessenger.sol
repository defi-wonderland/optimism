// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { HookData } from "interfaces/L2/IMessageHooks.sol";

struct Identifier {
    address origin;
    uint256 blockNumber;
    uint256 logIndex;
    uint256 timestamp;
    uint256 chainId;
}

/// @title IL2ToL2CrossDomainMessenger
/// @notice Interface for the L2ToL2CrossDomainMessenger contract.
interface IL2ToL2CrossDomainMessenger {
    /// @notice Thrown when a non-written slot in transient storage is attempted to be read from.
    error NotEntered();

    /// @notice Thrown when attempting to relay a message where payload origin is not L2ToL2CrossDomainMessenger.
    error IdOriginNotL2ToL2CrossDomainMessenger();

    /// @notice Thrown when the payload provided to the relay is not a SentMessage event.
    error EventPayloadNotSentMessage();

    /// @notice Thrown when attempting to send a message to the chain that the message is being sent from.
    error MessageDestinationSameChain();

    /// @notice Thrown when attempting to relay a message whose destination chain is not the chain relaying it.
    error MessageDestinationNotRelayChain();

    /// @notice Thrown when attempting to relay a message whose target is L2ToL2CrossDomainMessenger.
    error MessageTargetL2ToL2CrossDomainMessenger();

    /// @notice Thrown when attempting to relay a message that has already been relayed.
    error MessageAlreadyRelayed();

    /// @notice Thrown when a reentrant call is detected.
    error ReentrantCall();

    /// @notice Thrown when the provided message parameters do not match any hash of a previously sent message.
    error InvalidMessage();

    /// @notice Thrown when a hook call fails.
    error HookCallFailed(address hook, bytes returnData);

    /// @notice Thrown when a hook address doesn't implement the required interface.
    error InvalidHookInterface(address hook, bytes4 interfaceId);

    /// @notice Thrown when a bundle caller doesn't implement the required bundle interface.
    error InvalidBundleInterface(address caller, bytes4 interfaceId);

    /// @notice Emitted whenever a message is sent to a destination
    /// @param destination  Chain ID of the destination chain.
    /// @param target       Target contract or wallet address.
    /// @param messageNonce Nonce associated with the messsage sent
    /// @param sender       Address initiating this message call
    /// @param relayHook    Hook data for relay callback (encoded in message, executed on destination chain).
    /// @param message      Message payload to call target with.
    event SentMessage(uint256 destination, address target, uint256 messageNonce, address sender, HookData relayHook, bytes message);

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param source       Chain ID of the source chain.
    /// @param messageNonce Nonce associated with the messsage sent
    /// @param messageHash  Hash of the message that was relayed.
    /// @param returnDataHash Hash of the return data from the message that was relayed.
    event RelayedMessage(
        uint256 indexed source, uint256 indexed messageNonce, bytes32 indexed messageHash, bytes32 returnDataHash
    );

    function version() external view returns (string memory);

    /// @notice Mapping of message hashes to boolean receipt values. Note that a message will only
    ///         be present in this mapping if it has successfully been relayed on this chain, and
    ///         can therefore not be relayed again.
    /// @return Returns true if the message corresponding to the `_msgHash` was successfully relayed.
    function successfulMessages(bytes32) external view returns (bool);

    /// @notice Retrieves the next message nonce. Message version will be added to the upper two
    ///         bytes of the message nonce. Message version allows us to treat messages as having
    ///         different structures.
    /// @return Nonce of the next message to be sent, with added message version.
    function messageNonce() external view returns (uint256);

    /// @notice Mapping of message hashes to boolean sent values. Note that a message will only be present in this
    ///         mapping if it has been sent from this chain to a destination chain.
    function sentMessages(bytes32) external view returns (bool);

    /// @notice Retrieves the sender of the current cross domain message.
    /// @return sender_ Address of the sender of the current cross domain message.
    function crossDomainMessageSender() external view returns (address sender_);

    /// @notice Retrieves the source of the current cross domain message.
    /// @return source_ Chain ID of the source of the current cross domain message.
    function crossDomainMessageSource() external view returns (uint256 source_);

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return sender_ Address of the sender of the current cross domain message.
    /// @return source_ Chain ID of the source of the current cross domain message.
    function crossDomainMessageContext() external view returns (address sender_, uint256 source_);

    /// @notice Retrieves the bundle depth of the current cross domain message.
    /// @return depth_ Depth of the bundle.
    function messageBundleDepth() external view returns (uint256 depth_);

    /// @notice Retrieves the bundle hook hash of the current cross domain message.
    /// @return hookHash_ Hash of the bundle hook.
    function messageBundleHookHash() external view returns (bytes32 hookHash_);

    /// @notice Creates a bundle with the given hook and context.
    /// @param _bundleHook The hook data for the bundle.
    /// @param _context The context of the bundle.
    function createBundle(HookData calldata _bundleHook, bytes calldata _context) external;

    /// @notice Relays a bundle with the given context.
    /// @param _context The context of the bundle.
    function relayBundle(bytes calldata _context) external;

    /// @notice Sends a message to some target address on a destination chain. Note that if the call
    ///         always reverts, then the message will be unrelayable, and any ETH sent will be
    ///         permanently locked. The same will occur if the target on the other chain is
    ///         considered unsafe (see the _isUnsafeTarget() function).
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.
    /// @param _message     Message to trigger the target address with.
    /// @return messageHash_ The hash of the message being sent, used to track whether the message
    ///                      has successfully been relayed.
    function sendMessage(
        uint256 _destination,
        address _target,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_);

    /// @notice Sends a message to some target address on a destination chain with hooks for send and relay callbacks.
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.
    /// @param _sendHook    Hook data for send callback (executed immediately on source chain).
    /// @param _relayHook   Hook data for relay callback (encoded in message, executed on destination chain).
    /// @param _message     Message payload to call target with.
    /// @return messageHash_ The hash of the message being sent, used to track whether the message has successfully been
    /// relayed.
    function sendMessageWithHooks(
        uint256 _destination,
        address _target,
        HookData calldata _sendHook,
        HookData calldata _relayHook,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_);

    /// @notice Re-emits a previously sent message event for old messages that haven't been
    ///         relayed yet, allowing offchain infrastructure to pick them up and relay them.
    /// @dev    Emitting a message that has already been relayed will have no effect, as it is only
    ///         relayed once on the destination chain.
    /// @param _destination Chain ID of the destination chain.
    /// @param _nonce Nonce of the message sent
    /// @param _sender Address that sent the message
    /// @param _target Target contract or wallet address.
    /// @param _relayHook Relay hook data that was originally sent with the message.
    /// @param _message Message payload to call target with.
    /// @return messageHash_ The hash of the message being re-sent.
    function resendMessage(
        uint256 _destination,
        uint256 _nonce,
        address _sender,
        address _target,
        HookData calldata _relayHook,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_);

    /// @notice Relays a message that was sent by the other CrossDomainMessenger contract. Can only
    ///         be executed via cross-chain call from the other messenger OR if the message was
    ///         already received once and is currently being replayed.
    /// @param _id          Identifier of the SentMessage event to be relayed
    /// @param _sentMessage Message payload of the `SentMessage` event
    /// @return returnData_ Return data from the target contract call.
    function relayMessage(
        Identifier calldata _id,
        bytes calldata _sentMessage
    )
        external
        payable
        returns (bytes memory returnData_);

    function messageVersion() external view returns (uint16);

    function __constructor__() external;
}
