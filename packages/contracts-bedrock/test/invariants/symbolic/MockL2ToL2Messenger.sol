// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "src/L2/L2ToL2CrossDomainMessenger.sol";
import "forge-std/Test.sol";

contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    uint256 internal messageNonce;
    address internal immutable CURRENT_XDOMAIN_SENDER;

    constructor(address _currentXDomSender) {
        // Setting the current cross domain sender for the check of sender address equals the supertoken address
        CURRENT_XDOMAIN_SENDER = _currentXDomSender;
    }

    function sendMessage(uint256 _destination, address _target, bytes calldata) external payable {
        // TODO: Disable checks?
        if (_destination == block.chainid) revert MessageDestinationSameChain();
        if (_target == Predeploys.CROSS_L2_INBOX) revert MessageTargetCrossL2Inbox();
        if (_target == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert MessageTargetL2ToL2CrossDomainMessenger();

        // bytes memory data = abi.encodeCall(
        //     L2ToL2CrossDomainMessenger.relayMessage,
        //     (_destination, block.chainid, ++messageNonce, msg.sender, _target, _message)
        // );
        // assembly {
        //     log0(add(data, 0x20), mload(data))
        // }
    }

    function relayMessage(
        uint256 _destination,
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message
    )
        external
        payable
    {
        // TODO: Add more logic? Like replacing the `TSTORE` updates with `SSTORE` - or add the checks

        (bool succ, bytes memory ret) = _target.call{ value: msg.value }(_message);
        if (!succ) revert(string(ret));
    }

    function crossDomainMessageSource() external view returns (uint256 _source) {
        _source = block.chainid + 1;
    }

    function crossDomainMessageSender() external view returns (address _sender) {
        _sender = CURRENT_XDOMAIN_SENDER;
    }
}
