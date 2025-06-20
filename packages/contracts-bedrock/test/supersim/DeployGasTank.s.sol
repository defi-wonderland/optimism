// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { GasTank } from "src/L2/GasTank.sol";
import "forge-std/console.sol";

// To deploy on OPChainA (ChainID 901), run from packages/contracts-bedrock:
// forge script test/supersim/DeployGasTank.s.sol:DeployGasTank --rpc-url http://127.0.0.1:9545 --broadcast

// To deploy on OPChainB (ChainID 902), run from packages/contracts-bedrock:
// forge script test/supersim/DeployGasTank.s.sol:DeployGasTank --rpc-url http://127.0.0.1:9546 --broadcast

contract DeployGasTank is Script {
    // Private key for the first account (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) provided by supersim/anvil
    uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        GasTank gasTank = new GasTank();
        vm.stopBroadcast();

        address deployedAddress = address(gasTank);
        uint256 chainId = block.chainid;

        console.log("GasTank deployed on chain", chainId, "at address", deployedAddress);

        string memory json = vm.serializeAddress("", "address", deployedAddress);

        // Construct the file path inside the supersim test folder.
        string memory path = string(abi.encodePacked("test/supersim/gastank-", vm.toString(chainId), ".json"));

        // Write the JSON to a file.
        vm.writeJson(json, path);

        console.log("Deployment info written to", path);

        return deployedAddress;
    }
}
