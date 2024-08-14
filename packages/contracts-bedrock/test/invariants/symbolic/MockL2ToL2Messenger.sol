// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "src/L2/L2ToL2CrossDomainMessenger.sol";
import "forge-std/Console.sol";

// TODO: move to another file or import it
interface ITestL2ToL2CrossDomainMessenger {
    /// @notice Retrieves the sender of the current cross domain message.
    /// @return _sender Address of the sender of the current cross domain message.
    function crossDomainMessageSender() external view returns (address _sender);

    /// @notice Retrieves the source of the current cross domain message.
    /// @return _source Chain ID of the source of the current cross domain message.
    function crossDomainMessageSource() external view returns (uint256 _source);

    /// @notice Sends a message to some target address on a destination chain. Note that if the call
    ///         always reverts, then the message will be unrelayable, and any ETH sent will be
    ///         permanently locked. The same will occur if the target on the other chain is
    ///         considered unsafe (see the _isUnsafeTarget() function).
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.
    /// @param _message     Message to trigger the target address with.
    function sendMessage(uint256 _destination, address _target, bytes calldata _message) external payable;

    /// @notice Relays a message that was sent by the other CrossDomainMessenger contract. Can only
    ///         be executed via cross-chain call from the other messenger OR if the message was
    ///         already received once and is currently being replayed.
    /// @param _destination Chain ID of the destination chain.
    /// @param _nonce       Nonce of the message being relayed.
    /// @param _sender      Address of the user who sent the message.
    /// @param _source      Chain ID of the source chain.
    /// @param _target      Address that the message is targeted at.
    /// @param _message     Message to send to the target.
    function relayMessage(
        uint256 _destination,
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message
    )
        external
        payable;
}

contract MockL2ToL2Messenger is ITestL2ToL2CrossDomainMessenger {
    uint256 internal messageNonce;
    address internal currentXDomSender;

    constructor(address _currentXDomSender) {
        currentXDomSender = _currentXDomSender;
    }

    // TODO
    function sendMessage(uint256 _destination, address _target, bytes calldata _message) external payable {
        console.log(11);
        if (_destination == block.chainid) revert MessageDestinationSameChain();
        console.log(22);
        if (_target == Predeploys.CROSS_L2_INBOX) revert MessageTargetCrossL2Inbox();
        console.log(33);
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
        // _currentXDomSender = msg.sender;
        // messageNonce++;
        // TODO: Add more logic? Like replacing the `TSTORE` updates with `SSTORE` - or add the checks

        (bool succ, bytes memory ret) = _target.call{ value: msg.value }(_message);

        if (!succ) revert(string(ret));
    }

    // TODO
    function crossDomainMessageSource() external view returns (uint256 _source) {
        _source = block.chainid;
    }

    function crossDomainMessageSender() external view returns (address _sender) {
        _sender = currentXDomSender;
    }
}
