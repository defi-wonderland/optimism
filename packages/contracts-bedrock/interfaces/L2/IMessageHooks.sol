// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Hook data structure for message lifecycle callbacks
struct HookData {
    address hook;        // Hook contract address
    bytes hookPayload;   // Encoded call data for the hook
}

/// @title IMessageSentHook
/// @notice Interface for contracts that want to be notified when a message is sent
/// @dev Implementations MUST check that msg.sender is the L2ToL2CrossDomainMessenger
interface IMessageSentHook {
    /// @notice Called when a message is sent via L2ToL2CrossDomainMessenger
    /// @dev Hook implementations should verify msg.sender == L2ToL2CrossDomainMessenger
    ///      eventData can be decoded to extract message context if needed
    ///      eventData format: abi.encode(sender, relayHookHash, message, relayHook)
    /// @param eventData Encoded event data from the SentMessage event
    /// @param hookPayload Custom data from the hook
    function onMessageSent(
        bytes calldata eventData,
        bytes calldata hookPayload
    ) external;
}

/// @title IMessageRelayedHook
/// @notice Interface for contracts that want to be notified when a message is relayed
/// @dev Implementations MUST check that msg.sender is the L2ToL2CrossDomainMessenger
interface IMessageRelayedHook {
    /// @notice Called when a message is successfully relayed via L2ToL2CrossDomainMessenger
    /// @dev Hook implementations should verify msg.sender == L2ToL2CrossDomainMessenger
    ///      sentMessageData can be decoded to extract full message context if needed
    ///      Use _decodeSentMessagePayload logic to extract context from sentMessageData
    /// @param sentMessageData The complete sent message payload that was relayed
    /// @param hookPayload Custom data from the hook
    function onMessageRelayed(
        bytes calldata sentMessageData,
        bytes calldata hookPayload
    ) external;
} 