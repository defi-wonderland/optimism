// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IMessageSentHook, IMessageRelayedHook } from "interfaces/L2/IMessageHooks.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title MockSendHook
/// @notice Mock contract for testing send hooks
contract MockSendHook is IMessageSentHook {
    event OnMessageSentCalled(bytes eventData, bytes hookPayload);
    
    bool public shouldRevert;
    bytes public revertData;
    
    function setShouldRevert(bool _shouldRevert, bytes memory _revertData) external {
        shouldRevert = _shouldRevert;
        revertData = _revertData;
    }
    
    function onMessageSent(bytes calldata eventData, bytes calldata hookPayload) external override {
        // Verify caller is L2ToL2CrossDomainMessenger
        require(msg.sender == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, "MockSendHook: invalid caller");
        
        if (shouldRevert) {
            bytes memory data = revertData;
            assembly {
                revert(add(32, data), mload(data))
            }
        }
        emit OnMessageSentCalled(eventData, hookPayload);
    }
}

/// @title MockRelayHook
/// @notice Mock contract for testing relay hooks
contract MockRelayHook is IMessageRelayedHook {
    event OnMessageRelayedCalled(bytes sentMessageData, bytes hookPayload);
    
    bool public shouldRevert;
    bytes public revertData;
    
    function setShouldRevert(bool _shouldRevert, bytes memory _revertData) external {
        shouldRevert = _shouldRevert;
        revertData = _revertData;
    }
    
    function onMessageRelayed(bytes calldata sentMessageData, bytes calldata hookPayload) external override {
        // Verify caller is L2ToL2CrossDomainMessenger
        require(msg.sender == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, "MockRelayHook: invalid caller");
        
        if (shouldRevert) {
            bytes memory data = revertData;
            assembly {
                revert(add(32, data), mload(data))
            }
        }
        emit OnMessageRelayedCalled(sentMessageData, hookPayload);
    }
} 