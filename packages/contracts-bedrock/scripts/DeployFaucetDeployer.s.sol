// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { FaucetDeployer } from "src/L1/FaucetDeployer.sol";

/// @title DeployFaucetDeployer
/// @notice Script to deploy the FaucetDeployer contract on L1.
///         The FaucetDeployer is used by multisigs (via delegatecall) to deploy
///         and manage NativeAssetFaucet contracts on L2.
contract DeployFaucetDeployer is Script {
    /// @notice The CREATE2 Deployer predeploy address on L2
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    function run() external {
        // Get environment variables
        address payable portal = payable(vm.envAddress("PORTAL"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== DeployFaucetDeployer ===");
        console.log("Portal:", portal);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);

        vm.startBroadcast(deployerPrivateKey);

        FaucetDeployer faucetDeployer = new FaucetDeployer(IOptimismPortal2(portal), CREATE2_DEPLOYER);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("FaucetDeployer deployed at:", address(faucetDeployer));
        console.log("\nUsage:");
        console.log("1. From LiquidityController owner (Safe), delegatecall:");
        console.log("   faucetDeployer.deployAndAuthorize(faucetOwner, permissionlessAmount, gasLimit)");
        console.log("2. From faucet owner (Safe), delegatecall:");
        console.log("   faucetDeployer.mint(faucetAddress, recipient, amount, gasLimit)");
    }
}
