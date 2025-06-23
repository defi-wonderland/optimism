// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { GasTank } from "src/L2/GasTank.sol";
import { MessageSender } from "./MessageSender.sol";
import "forge-std/console.sol";

// To deploy every contract on both chains, run from packages/contracts-bedrock:
// forge script test/supersim/SetupSupersim.s.sol:SetupSupersim --broadcast

contract SetupSupersim is Script {
    uint256 constant ORIGIN_CHAIN_ID = 901;
    uint256 constant DESTINATION_CHAIN_ID = 902;
    string constant ORIGIN_CHAIN_RPC_URL = "http://127.0.0.1:9545";
    string constant DESTINATION_CHAIN_RPC_URL = "http://127.0.0.1:9546";
    uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        bytes32 dynamicSalt = bytes32(block.timestamp);

        // --- Deploy to Origin Chain (901) ---
        vm.createSelectFork(ORIGIN_CHAIN_RPC_URL);
        vm.startBroadcast(deployerPrivateKey);

        GasTank gasTank901 = new GasTank{ salt: dynamicSalt }();

        vm.stopBroadcast();
        console.log("GasTank deployed on chain %d at address %s", ORIGIN_CHAIN_ID, address(gasTank901));

        // --- Deploy to Destination Chain (902) ---
        vm.createSelectFork(DESTINATION_CHAIN_RPC_URL);
        vm.startBroadcast(deployerPrivateKey);

        GasTank gasTank902 = new GasTank{ salt: dynamicSalt }();
        MessageSender messageSender902 = new MessageSender();

        vm.stopBroadcast();
        console.log("GasTank deployed on chain %d at address %s", DESTINATION_CHAIN_ID, address(gasTank902));
        console.log("MessageSender deployed on chain %d at address %s", DESTINATION_CHAIN_ID, address(messageSender902));

        // --- Create a single JSON file for all contracts ---
        string memory path = "test/supersim/supersim-contracts.json";

        // To ensure we're overwriting, we remove the old file first.
        // A try/catch is used to avoid an error if the file doesn't exist.
        try vm.removeFile(path) { } catch { }

        string memory json = string(
            abi.encodePacked(
                '{"gasTank901":"',
                vm.toString(address(gasTank901)),
                '","gasTank902":"',
                vm.toString(address(gasTank902)),
                '","messageSender902":"',
                vm.toString(address(messageSender902)),
                '"}'
            )
        );
        vm.writeFile(path, json);
        console.log("Deployment info written to %s", path);
    }
}
