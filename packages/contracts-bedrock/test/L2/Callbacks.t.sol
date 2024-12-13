// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import {
    CallbackEntrypoint,
    Greeter,
    CallbackContext,
    IERC20,
    Identifier,
    IL2ToL2CrossDomainMessenger
} from "src/L2/Callbacks.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { IDependencySet } from "interfaces/L2/IDependencySet.sol";

import "forge-std/Test.sol";

contract Counter {
    function two() public pure returns (uint256) {
        return 2;
    }
}

contract CallbackTest is Test {
    CallbackEntrypoint public entrypointA;
    CallbackEntrypoint public entrypointB;

    Greeter public greeterA;
    Greeter public greeterB;

    string public greeting = "Hello, World!";

    Counter public counter;

    uint64 chainIdA = 1;
    uint64 chainIdB = 2;

    address public user;

    function setUp() public {
        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger()).code);

        counter = new Counter();

        entrypointA = new CallbackEntrypoint();
        entrypointB = new CallbackEntrypoint();

        greeterA = new Greeter(greeting, IERC20(address(0)));
        greeterB = new Greeter(greeting, IERC20(address(0)));

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

        bytes4 _finalTargetCall = Counter.two.selector;
        greeterA.remoteGreet(CallbackContext({ to: address(counter), selector: _finalTargetCall }));

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
        _mockAndExpect(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), // , abi.encode(id,
                // keccak256(sentMessage))),
            ""
        );

        console.log("heere1");

        entrypointB.relayMessage(id, sentMessage);

        console.log("heere");

        /* 3. Chain A: CDM.relayMessage -> remoteGreetCallback -> target call */
        // Chain ID 1 == A
        vm.chainId(chainIdA);

        // Ensure the CrossL2Inbox validates this message
        _mockAndExpect(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeWithSelector(ICrossL2Inbox.validateMessage.selector), // , abi.encode(id,
                // keccak256(sentMessage))),
            ""
        );

        sentMessage = abi.encodePacked(
            abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, chainIdA, address(greeterA), _cdmNonce), // topics
            abi.encode(address(entrypointB), _finalTargetCall, address(greeterA)) // data
        );
    }
}
