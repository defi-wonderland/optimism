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

/// @notice This is the contract that will be called by the callback. It only stores what it receives.
contract Receiver {
    event GreetingReceived(string greeting, uint256 balance);

    string public receivedGreeting;
    uint256 public receivedBalance;

    function receiveGreetings(string memory _greeting, uint256 _balance) external {
        receivedGreeting = _greeting;
        receivedBalance = _balance;

        emit GreetingReceived(_greeting, _balance);
    }
}

contract CallbackTest is Test {
    address public constant CDM = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    uint256 public CDM_NONCE = 1;
    address public NO_CUSTOM_ENTRYPOINT = address(0);

    string public greetingA = "Hello, World from Chain A!";
    string public greetingB = "Hello, World from Chain B!";

    uint64 chainA = 1;
    uint64 chainB = 2;

    CallbackGreeter public greeterA;
    CallbackGreeter public greeterB;
    CallbackEntrypoint public entrypointB;
    Receiver public receiver;

    address public owner;
    address public relayer;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger()).code);

        // Deploy and setup entrypointB and greeters on both chains
        entrypointB = new CallbackEntrypoint();

        vm.chainId(chainB);

        greeterB = new CallbackGreeter(greetingB, address(0));
        vm.label(address(greeterB), "greeterB");

        vm.chainId(chainA);
        greeterA = new CallbackGreeter(greetingA, address(entrypointB));
        vm.label(address(greeterA), "greeterA");

        vm.chainId(chainB);
        greeterA.setRemoteGreeter(address(greeterB));
        greeterB.setRemoteGreeter(address(greeterA));

        // Deploy target contract on destination
        receiver = new Receiver();

        vm.stopPrank();
    }

    /// @notice Tests the callback functionality. the complete flow is as follows:
    ///         1. Chain A: remoteGreet() -> async() -> sendMessage()
    ///         2. Chain B:  entrypoint.relayMessage() -> cdm.relayMessage() -> greeting() + remoteGreetCallback(nonce, )
    ///                       -> sendMessage(chainA, greeterA, remoteGreetCallback(nonce, ))
    ///         3. Chain A: CDM.relayMessage -> remoteGreetCallback -> target call
    function testCallback() public {
        /**
         * Step 1 - Chain A - trigger call on destination
         */
        vm.chainId(chainA);

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        // Selector of the function to be executed once the callback is received
        bytes4 callbackContextSelector = Receiver.receiveGreetings.selector;

        // Construct the callback call with the target and selector and call `remoteGreeter()`
        vm.prank(owner);
        greeterA.remoteGreet(
            chainB,
            ICallbackGreeterMetadata.CallbackContext({ to: address(receiver), selector: callbackContextSelector })
        );

        // Get the context that was stored and sent on the message
        uint224 callbackNonce = greeterA.returnContextNonce();

        /**
         * Step 2 - Chain B - relay message on destination and send message back
         */
        vm.chainId(chainB);

        // Construct the message identifier
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, 1, 1, 1, 1);

        // Define the message that was built on the `async` function, when the message was sent in origin
        bytes memory message =
            abi.encodePacked(abi.encodeWithSignature("greeting()"), callbackContextSelector, callbackNonce);

        // Build the whole message to be relayed by the entrypoint
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainB, address(greeterB), CDM_NONCE), // topics
            abi.encode(address(greeterA), address(entrypointB), message) // data
        );

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall(Predeploys.CROSS_L2_INBOX, abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), "");

        // Relay the message on the entrypoint
        vm.prank(relayer);
        bytes memory returnData = entrypointB.relayMessage(id, sentMessage);

        /**
         * Step 3 - Chain A - callback
         */
        vm.chainId(chainA);

        // Define the message that was built on the entrypoint, when the message was sent back to origin
        message = abi.encodeWithSelector(CallbackGreeter.remoteGreetCallback.selector, callbackNonce, returnData);

        // Build the whole message to be relayed by the CDM
        sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainA, address(greeterA), CDM_NONCE), // topics
            abi.encode(address(greeterB), NO_CUSTOM_ENTRYPOINT, message) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall(Predeploys.CROSS_L2_INBOX, abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), "");

        // Relay the message on the CDM
        vm.prank(relayer);
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(id, sentMessage);

        // Check the receiver contract state to ensure the callback was properly executed
        assertEq(abi.encodePacked(receiver.receivedGreeting()), abi.encodePacked(greeterB.greeting()));
        assertEq(receiver.receivedBalance(), 0);
    }
}
