// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "src/L2/L2ToL2CrossDomainMessenger.sol";

// TODO: Try to merge to a single mocked contract used by fuzzing and symbolic invariant tests - only if possible
// and low priorty
contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    // Setting the current cross domain sender for the check of sender address equals the supertoken address
    address internal immutable CROSS_DOMAIN_SENDER;

    constructor(address _xDomainSender) {
        CROSS_DOMAIN_SENDER = _xDomainSender;
    }

    function sendMessage(uint256 _destination, address _target, bytes calldata) external payable {
        // TODO: Disable checks?
        if (_destination == block.chainid) revert MessageDestinationSameChain();
        if (_target == Predeploys.CROSS_L2_INBOX) revert MessageTargetCrossL2Inbox();
        if (_target == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert MessageTargetL2ToL2CrossDomainMessenger();
    }

    function relayMessage(
        uint256,
        uint256,
        uint256,
        address,
        address _target,
        bytes calldata _message
    )
        external
        payable
    {
        // TODO: Add checks?

        // TODO: Not sure if this is needed at all if halmos will be used for stateful tests. But will remain for now.
        (bool succ, bytes memory ret) = _target.call{ value: msg.value }(_message);
        if (!succ) revert(string(ret));

        // TODO: Add more logic? Like replacing the `TSTORE` updates with `SSTORE` - or add the checks
    }

    function crossDomainMessageSource() external view returns (uint256 _source) {
        _source = block.chainid + 1;
    }

    function crossDomainMessageSender() external view returns (address _sender) {
        _sender = CROSS_DOMAIN_SENDER;
    }
}
