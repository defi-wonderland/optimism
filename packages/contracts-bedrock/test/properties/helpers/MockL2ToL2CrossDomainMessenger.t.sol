// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

contract MockL2ToL2CrossDomainMessenger {
    ////////////////////////
    //  type definitions  //
    ////////////////////////
    struct CrossChainMessage {
        address crossDomainMessageSender;
        address crossDomainMessageSource;
        bytes payload;
    }

    /////////////////////////////////////////////////////////
    //  State vars mocking the L2toL2CrossDomainMessenger  //
    /////////////////////////////////////////////////////////
    address public crossDomainMessageSender;
    address public crossDomainMessageSource;

    ///////////////////////////////////////////////////
    //  Helpers for cross-chain interaction mocking  //
    ///////////////////////////////////////////////////
    mapping(address supertoken => bytes32 deploySalt) public superTokenInitDeploySalts;
    mapping(uint256 chainId => mapping(bytes32 deploySalt => address supertoken)) public superTokenAddresses;

    CrossChainMessage[] private _messageQueue;
    bool private _atomic;

    function crossChainMessageReceiver(
        address sender,
        uint256 destinationChainId
    )
        external
        view
        returns (OptimismSuperchainERC20)
    {
        return OptimismSuperchainERC20(superTokenAddresses[destinationChainId][superTokenInitDeploySalts[sender]]);
    }

    function setCrossDomainMessageSender(address sender) external {
        crossDomainMessageSender = sender;
    }

    function registerSupertoken(bytes32 deploySalt, uint256 chainId, address token) external {
        superTokenAddresses[chainId][deploySalt] = token;
        superTokenInitDeploySalts[token] = deploySalt;
    }

    function messageQueueLength() public view returns (uint256) {
        return _messageQueue.length;
    }

    function setAtomic(bool atomic) public {
        _atomic = atomic;
    }

    function relayMessageFromQueue(uint256 index) public {
        CrossChainMessage memory message = _messageQueue[index];
        _messageQueue[index] = _messageQueue[_messageQueue.length - 1];
        _messageQueue.pop();
        _relayMessage(message);
    }

    function _relayMessage(CrossChainMessage memory message) internal {
        crossDomainMessageSender = message.crossDomainMessageSender;
        crossDomainMessageSource = message.crossDomainMessageSource;
        SafeCall.call(crossDomainMessageSender, 0, message.payload);
        crossDomainMessageSender = address(0);
        crossDomainMessageSource = address(0);
    }

    ////////////////////////////////////////////////////////
    //  Functions mocking the L2toL2CrossDomainMessenger  //
    ////////////////////////////////////////////////////////

    /// @notice recipient will not be used since in normal execution it's the same
    /// address on a different chain, but here we have to compute it to mock
    /// cross-chain messaging
    function sendMessage(uint256 chainId, address, /*recipient*/ bytes memory data) external {
        address crossChainRecipient = superTokenAddresses[chainId][superTokenInitDeploySalts[msg.sender]];
        if (crossChainRecipient == msg.sender) {
            require(false, "same chain");
        }
        CrossChainMessage memory message = CrossChainMessage({
            crossDomainMessageSender: crossChainRecipient,
            crossDomainMessageSource: msg.sender,
            payload: data
        });

        if (_atomic) {
            _relayMessage(message);
        } else {
            _messageQueue.push(message);
        }
    }
}
