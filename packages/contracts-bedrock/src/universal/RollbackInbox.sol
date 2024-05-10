// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract RollbackInbox {
    // Note: this is not handling initialization of these variables
    address public otherMessenger; // CrossDomainMessenger from the other domain
    CrossDomainMessenger public messenger; // CrossDomainMessenger from this domain

    mapping(bytes32 => uint256) messageHashes;

    event MessageHashReceived(bytes32 messageHash, uint256 timestamp);

    function receiveMessageHash(bytes32 _messageHash, address _sender) public {
        require(
            messenger.xDomainMsgSender == address(otherMessenger),
            "RollbackInbox: only CrossDomainMessenger from other domain can be the sender"
        );
        require(
            msg.sender == address(messenger),
            "RollbackInbox: only CrossDomainMessenger from this domain can be the caller"
        );
        require(
            messenger.successfulMessages[_messageHash] == 0,
            "RollbackInbox: can not process already successful message hashes"
        );

        messageHashes[_messageHash] = block.timestamp;
        emit MessageHashReceived(messageHash, block.timestamp);
    }
}
