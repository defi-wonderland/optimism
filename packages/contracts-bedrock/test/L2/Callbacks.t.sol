// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import {
    CallbackEntrypoint,
    CallbackGreeter,
    ICallbackGreeterMetadata,
    Identifier,
    IL2ToL2CrossDomainMessenger
} from "src/L2/Callbacks.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { IDependencySet } from "interfaces/L2/IDependencySet.sol";

import "forge-std/Test.sol";

/// @notice This is the contract that will be called by the callback.
///         CallbackGreeter expects to have the the whatever function we choose to have a specific signature.
contract Receiver {
    event GreetingReceived(string greeting, uint256 balance);

    string public receivedGreeting;
    uint256 public receivedBalance;

    function receiveGreetings(string memory _greeting, uint256 _balance) external returns (bool _balanceIsZero) {
        receivedGreeting = _greeting;
        receivedBalance = _balance;

        emit GreetingReceived(_greeting, _balance);
    }
}

contract CallbackTest is Test {
    address public constant CDM = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    CallbackEntrypoint public entrypointB;

    CallbackGreeter public greeterA;
    CallbackGreeter public greeterB;

    string public greetingA = "Hello, World from Chain A!";
    string public greetingB = "Hello, World from Chain B!";

    uint64 chainA = 1;
    uint64 chainB = 2;

    Receiver public receiver;

    address public owner;
    address public relayer;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger()).code);

        // Deploy and setup entrypointB and greeters on both chains
        entrypointB = new CallbackEntrypoint();

        greeterA = new CallbackGreeter(greetingA, address(entrypointB));
        greeterB = new CallbackGreeter(greetingB, address(0));

        greeterA.setRemoteGreeter(address(greeterB));
        greeterB.setRemoteGreeter(address(greeterA));

        // Deploy target contract on destination
        receiver = new Receiver();

        vm.stopPrank();
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Tests the callback functionality. the complete flow is as follows:
    ///         1. Chain A: remoteGreet() -> async() -> sendMessage()
    ///         2. Chain B:  entrypoint.relayMessage() -> cdm.relayMessage() -> greeting() + remoteGreetCallback(nonce, )
    /// ->
    ///            sendMessage(chainA, greeterA, remoteGreetCallback(nonce, ))
    ///         3. Chain A: CDM.relayMessage -> remoteGreetCallback -> target call
    function testCallback() public {
        /* Step 1 - Chain A - trigger call on destination */
        vm.chainId(chainA);

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        // Construct the callback call with the target and selector and call `remoteGreeter()`
        vm.prank(owner);
        bytes4 _callbackSelector = Receiver.receiveGreetings.selector;
        greeterA.remoteGreet(
            chainB, ICallbackGreeterMetadata.CallbackContext({ to: address(receiver), selector: _callbackSelector })
        );

        // Get the context
        uint224 callbackNonce = greeterA.returnContextNonce();

        /* Step 2 - Chain B - relay message on destination and send message back */
        vm.chainId(chainB);

        // Construct the SentMessage payload & identifier
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, 1, 1, 1, 1);

        uint256 cdmNonce = 1;
        bytes memory targetCalladata = abi.encodeWithSignature("greeting()");
        bytes memory message =
            abi.encodePacked(targetCalladata, CallbackGreeter.remoteGreetCallback.selector, callbackNonce);

        bytes memory sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainB, address(greeterB), cdmNonce), // topics
            abi.encode(address(greeterA), message, address(entrypointB)) // data
        );

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        // Ensure the CrossL2Inbox validates this message
        _mockAndExpect(Predeploys.CROSS_L2_INBOX, abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), "");

        vm.prank(relayer);
        bytes memory _returnData = entrypointB.relayMessage(id, sentMessage);

        /* Step 3 - Chain A - callback */
        vm.chainId(chainA);

        message = abi.encodeCall(CallbackGreeter.remoteGreetCallback, (callbackNonce, string(_returnData)));
        // message = abi.encodeWithSelector(CallbackGreeter.remoteGreetCallback.selector, callbackNonce, _returnData);
        sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainA, address(greeterA), cdmNonce), // topics
            abi.encode(address(entrypointB), message, address(0)) // data
        );

        // Ensure the CrossL2Inbox validates this message
        _mockAndExpect(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), // , abi.encode(id,
            ""
        );

        vm.prank(relayer);
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(id, sentMessage);

        console.log("received callback Greeting on origin");
        console.logString(receiver.receivedGreeting());

        console.log("actual greeting");
        console.logString(greetingB);

        // Check the receiver contract state
        assertEq(abi.encodePacked(receiver.receivedGreeting()), abi.encodePacked(greetingB), "1");
        assertEq(receiver.receivedBalance(), 0);
    }
}
