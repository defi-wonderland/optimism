// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import {
    CallbackEntrypoint, Greeter, CallbackContext, Identifier, IL2ToL2CrossDomainMessenger
} from "src/L2/Callbacks.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { IDependencySet } from "interfaces/L2/IDependencySet.sol";

import "forge-std/Test.sol";

/// @notice This is the contract that will be called by the callback.
///         Greeter expects to have the the whatever function we choose to have a specific signature.
contract Receiver {
    function receiveGreetings(string memory, uint256 _balance) external returns (bool) {
        return _balance != 0;
    }
}

contract CallbackTest is Test {
    CallbackEntrypoint public entrypointA;
    CallbackEntrypoint public entrypointB;

    Greeter public greeterA;
    Greeter public greeterB;

    string public greetingA = "Hello, World from Chain A!";
    string public greetingB = "Hello, World from Chain B!";

    Receiver public receiver;

    uint64 chainIdA = 1;
    uint64 chainIdB = 2;

    address public user;

    function setUp() public {
        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger()).code);

        receiver = new Receiver();

        entrypointA = new CallbackEntrypoint();
        entrypointB = new CallbackEntrypoint();

        greeterA = new Greeter(greetingA);
        greeterB = new Greeter(greetingB);

        greeterA.setRemoteGreeter(address(greeterB));
        greeterB.setRemoteGreeter(address(greeterA));
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    function testCallback() public {
        /* 1. Chain A: remoteGreet -> async -> sendMessage */
        // Chain ID 1 == A
        vm.chainId(chainIdA);

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        bytes4 _finalTargetCall = Receiver.receiveGreetings.selector;

        greeterA.remoteGreet(CallbackContext({ to: address(receiver), selector: _finalTargetCall }));

        /* 2. Chain B:  entrypoint.relayMessage -> cdm.relayMessage -> greeting + remoteGreetCallback(nonce, ) ->
        sendMessage(chainA, greeterA, remoteGreetCallback) */
        // Chain ID 2 == B
        vm.chainId(chainIdB);

        // Construct the SentMessage payload & identifier
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, 1, 1, 1, 1);

        uint256 _cdmNonce = 1;
        uint224 _greeterNonce = 1;

        bytes memory _data = abi.encodeWithSignature("greeting()");
        bytes memory _message = abi.encodePacked(_data, Greeter.remoteGreetCallback.selector, _greeterNonce);

        bytes memory sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainIdB, address(greeterB), _cdmNonce), // topics
            abi.encode(address(greeterA), _message, address(entrypointB)) // data
        );

        // Mock the call over the `isInDependencySet` function to return true
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(IDependencySet.isInDependencySet.selector),
            abi.encode(true)
        );

        // Ensure the CrossL2Inbox validates this message
        _mockAndExpect(Predeploys.CROSS_L2_INBOX, abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), "");

        bytes memory _returnData = entrypointB.relayMessage(id, sentMessage);

        /* 3. Chain A: CDM.relayMessage -> remoteGreetCallback -> target call */
        // Chain ID 1 == A
        vm.chainId(chainIdA);

        _message = abi.encodeCall(Greeter.remoteGreetCallback, (1, string(_returnData)));

        sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainIdA, address(greeterA), _cdmNonce), // topics
            abi.encode(address(entrypointB), _message, address(0x0)) // data
        );

        // Ensure the CrossL2Inbox validates this message
        _mockAndExpect(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), // , abi.encode(id,
            ""
        );

        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(id, sentMessage);
    }
}
