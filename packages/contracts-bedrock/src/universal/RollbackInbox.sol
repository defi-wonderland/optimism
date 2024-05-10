// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract RollbackInbox {
    // Note: this is not handling initialization of these variables
    address public otherMessenger; // CrossDomainMessenger from the other domain
    CrossDomainMessenger public messenger; // CrossDomainMessenger from this domain

    mapping(bytes32 => uint256) public messageHashes;

    event MessageHashReceived(bytes32 indexed messageHash, uint256 indexed timestamp);

    function receiveMessageHash(bytes32 _messageHash, address _sender) public {
        require(
            msg.sender == address(messenger),
            "RollbackInbox: only CrossDomainMessenger from this domain can be the caller"
        );
        require(
            messenger.xDomainMsgSender == address(otherMessenger),
            "RollbackInbox: only CrossDomainMessenger from other domain can be the sender"
        );

        messageHashes[_messageHash] = block.timestamp;
        emit MessageHashReceived(messageHash, block.timestamp);
    }
}
