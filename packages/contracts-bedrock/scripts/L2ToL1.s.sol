// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";

// Interfaces
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL2CrossDomainMessenger } from "interfaces/L2/IL2CrossDomainMessenger.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

// Libraries
import { Encoding } from "src/libraries/Encoding.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { FFIInterface } from "test/setup/FFIInterface.sol";

/// @title L2ToL1
/// @notice Script to simulate interactions on a L2 CGT (Custom Gas Token) chain.
contract L2ToL1 is Script {
    // L1 contracts
    IL1CrossDomainMessenger public l1CrossDomainMessenger;
    IOptimismPortal2 public optimismPortal;
    IDisputeGameFactory public disputeGameFactory;

    // L2 contracts
    IL2CrossDomainMessenger public l2CrossDomainMessenger;
    IL2ToL1MessagePasser public l2ToL1MessagePasser;

    // Config
    uint256 public l1Fork;
    uint256 public l2Fork;

    address public testAddress = makeAddr("testAddress");

    // Withdrawal tracking
    bytes32 public withdrawalHash;
    uint256 public withdrawalNonce;

    function run() public {
        setUp();
        _initiateWithdrawal();
    }

    function setUp() public {
        l1Fork = vm.createFork("http://127.0.0.1:8544"); // chainId 900
        l2Fork = vm.createFork("http://127.0.0.1:8545"); // chainId 901

        vm.selectFork(l2Fork);
        l2CrossDomainMessenger = IL2CrossDomainMessenger(payable(0x4200000000000000000000000000000000000007));
        l2ToL1MessagePasser = IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER));

        l1CrossDomainMessenger =
            IL1CrossDomainMessenger(payable(address(l2CrossDomainMessenger.l1CrossDomainMessenger())));

        vm.selectFork(l1Fork);
        optimismPortal = IOptimismPortal2(payable(address(l1CrossDomainMessenger.portal())));
        disputeGameFactory = IDisputeGameFactory(payable(address(optimismPortal.disputeGameFactory())));
        console.log("Optimism portal address:", address(optimismPortal));
        console.log("DisputeGameFactory address:", address(disputeGameFactory));
        console.log("Proof maturity delay seconds:", optimismPortal.proofMaturityDelaySeconds());
    }

    function _initiateWithdrawal() public returns (Types.WithdrawalTransaction memory, bytes32 txHash) {
        vm.selectFork(l2Fork);

        bytes memory message = abi.encodeCall(optimismPortal.isCustomGasToken, ());
        uint32 gasLimit = 1000000;

        console.log("Initiating withdrawal on L2...");

        // Record logs and broadcast the transaction
        vm.recordLogs();
        vm.broadcast();
        l2CrossDomainMessenger.sendMessage(address(0x1), message, gasLimit);
        console.log("Block number:", block.number);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Parse the MessagePassed event to get withdrawal details
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimitFromEvent;
        bytes memory data;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessagePassed(uint256,address,address,uint256,uint256,bytes,bytes32)"))
            {
                // Parse event data: nonce is in topics[1], sender in topics[2], target in topics[3]
                nonce = uint256(logs[i].topics[1]);
                sender = address(uint160(uint256(logs[i].topics[2])));
                target = address(uint160(uint256(logs[i].topics[3])));

                // Parse the data field for value, gasLimit, data, and withdrawalHash
                (value, gasLimitFromEvent, data, withdrawalHash) =
                    abi.decode(logs[i].data, (uint256, uint256, bytes, bytes32));

                console.log("Withdrawal hash:", vm.toString(withdrawalHash));
                withdrawalNonce = nonce;
                break;
            }
        }

        Types.WithdrawalTransaction memory _tx = Types.WithdrawalTransaction({
            nonce: nonce,
            sender: sender,
            target: target,
            value: value,
            gasLimit: gasLimitFromEvent,
            data: data
        });

        // Verify the withdrawal hash matches
        bytes32 computedHash = Hashing.hashWithdrawal(_tx);
        require(withdrawalHash == computedHash, "Withdrawal hash mismatch");

        return (_tx, txHash);
    }
}
