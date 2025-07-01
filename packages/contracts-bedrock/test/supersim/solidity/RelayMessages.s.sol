// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Vm, VmSafe } from "forge-std/Vm.sol";
import { GasTank } from "src/L2/GasTank.sol";
import { MessageSender } from "test/supersim/MessageSender.sol";
import { IL2ToL2CrossDomainMessenger, Identifier } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract RelayMessages is Script {
    // Private Keys Addresses
    uint256 constant DEPLOYER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant RELAYER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant RELAYER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    // Predeploy addresses
    address constant L2_TO_L2_MESSENGER = 0x4200000000000000000000000000000000000023;

    uint256 constant ORIGIN_CHAIN_ID = 901;
    uint256 constant DESTINATION_CHAIN_ID = 902;

    uint256 forkIdOrigin;
    uint256 forkIdDest;

    // Contract addresses from deployment
    GasTank gasTank901;
    GasTank gasTank902;
    address messageSender902;

    // Sent message data
    struct SentMessageData {
        uint256 destination;
        address target;
        address sender;
        bytes message;
    }

    function setUp() public {
        forkIdOrigin = vm.createFork(vm.rpcUrl("http://127.0.0.1:9545"));
        forkIdDest = vm.createFork(vm.rpcUrl("http://127.0.0.1:9546"));

        // Read contract addresses from JSON file
        string memory jsonData = vm.readFile("test/supersim/supersim-e2e-contracts.json");
        address gasTank901Addr = vm.parseJsonAddress(jsonData, ".gasTank901");
        address gasTank902Addr = vm.parseJsonAddress(jsonData, ".gasTank902");
        messageSender902 = vm.parseJsonAddress(jsonData, ".messageSender902");

        gasTank901 = GasTank(gasTank901Addr);
        gasTank902 = GasTank(gasTank902Addr);
    }

    function run() external {
        setUp();

        // Step 0: Message sent data
        SentMessageData memory sentMessageData = SentMessageData({
            destination: DESTINATION_CHAIN_ID,
            target: messageSender902,
            sender: DEPLOYER,
            message: abi.encodeCall(MessageSender.sendMessages, (ORIGIN_CHAIN_ID, uint256(10)))
        });

        // Step 1: Build identifier and payload from the sent message
        (Identifier memory identifier, bytes memory payload) = _buildIdentifierAndPayload(sentMessageData);
    }

    function _buildIdentifierAndPayload(SentMessageData memory sentMessageData)
        internal
        returns (Identifier memory identifier_, bytes memory payload_)
    {
        // Use Go function to get the latest SentMessage log and build identifier
        string[] memory cmds = new string[](8);
        cmds[0] = "go";
        cmds[1] = "run";
        cmds[2] = "test/supersim/helpers/main.go";
        cmds[3] = "build_id";
        cmds[4] = vm.toString(sentMessageData.destination);
        cmds[5] = vm.toString(sentMessageData.target);
        cmds[6] = vm.toString(sentMessageData.sender);
        cmds[7] = vm.toString(sentMessageData.message);

        bytes memory result = vm.ffi(cmds);
        string memory jsonResult = string(result);

        // Debug print for the FFI result
        require(bytes(jsonResult).length > 0, " returned empty result");

        // Parse the result from Go function
        identifier_.origin = vm.parseJsonAddress(jsonResult, ".identifier.origin");
        identifier_.blockNumber = vm.parseJsonUint(jsonResult, ".identifier.blockNumber");
        identifier_.logIndex = vm.parseJsonUint(jsonResult, ".identifier.logIndex");
        identifier_.timestamp = vm.parseJsonUint(jsonResult, ".identifier.timestamp");
        identifier_.chainId = vm.parseJsonUint(jsonResult, ".identifier.chainId");

        payload_ = vm.parseJsonBytes(jsonResult, ".payload");

        console.log("Built identifier:", vm.toString(identifier_.origin));
        console.log("Block number:", identifier_.blockNumber);
        console.log("Log index:", identifier_.logIndex);
        console.log("Payload length:", payload_.length);
    }
}
