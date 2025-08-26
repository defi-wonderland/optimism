// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";

// Interfaces
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL2CrossDomainMessenger } from "interfaces/L2/IL2CrossDomainMessenger.sol";

// Libraries
import { Encoding } from "src/libraries/Encoding.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";

/// @title L1ToL2
/// @notice Script to simulate interactions on a L1 CGT (Custom Gas Token) chain.
contract L1ToL2 is Script {
    // L1 contracts
    IL1CrossDomainMessenger public l1CrossDomainMessenger;

    // L2 contracts
    IL2CrossDomainMessenger public l2CrossDomainMessenger;

    // Config
    uint256 public l1Fork;
    uint256 public l2Fork;

    address public testAddress = makeAddr("testAddress");

    function run() public {
        setUp();
        _l1ToL2Interactions();
    }

    function setUp() public {
        l1Fork = vm.createFork("http://127.0.0.1:8544"); // chainId 900
        l2Fork = vm.createFork("http://127.0.0.1:8545"); // chainId 901

        vm.selectFork(l2Fork);
        l2CrossDomainMessenger = IL2CrossDomainMessenger(payable(0x4200000000000000000000000000000000000007));
        l1CrossDomainMessenger =
            IL1CrossDomainMessenger(payable(address(l2CrossDomainMessenger.l1CrossDomainMessenger())));
    }

    function _l1ToL2Interactions() public {
        // Send a message from L1 to L2
        vm.selectFork(l1Fork);
        bytes memory message = bytes("Hello from L1!");
        uint32 gasLimit = 1000000;

        console.log("Sending message from L1 to L2...");
        console.log("Target address:", address(testAddress));
        console.log("Message:", string(message));

        // Get the nonce before sending
        uint256 nonceBefore = l1CrossDomainMessenger.messageNonce();

        l1CrossDomainMessenger.sendMessage(address(testAddress), message, gasLimit);

        // Get the nonce after sending (this is the nonce of the message we just sent)
        uint256 messageNonce = nonceBefore;

        console.log("Message sent with nonce:", messageNonce);

        // Switch to L2 to relay the message
        vm.selectFork(l2Fork);

        // Encode the versioned nonce (version 1)
        uint256 versionedNonce = Encoding.encodeVersionedNonce(uint240(messageNonce), 1);

        // The sender of the message on L2 will be the aliased L1CrossDomainMessenger
        address l1Sender = address(l1CrossDomainMessenger);
        address aliasSender = AddressAliasHelper.applyL1ToL2Alias(l1Sender);

        console.log("Relaying message on L2...");
        console.log("Aliased sender:", aliasSender);
        console.log("Original L1 sender:", l1Sender);

        // Relay the message on L2
        vm.prank(aliasSender);
        l2CrossDomainMessenger.relayMessage(
            versionedNonce,
            l1Sender,
            address(testAddress),
            0, // value
            uint240(gasLimit),
            message
        );

        console.log("Message successfully relayed on L2!");
    }
}
