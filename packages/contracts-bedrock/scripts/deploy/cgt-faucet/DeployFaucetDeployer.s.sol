// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { FaucetDeployer } from "scripts/deploy/cgt-faucet/FaucetDeployer.sol";

/// @title DeployFaucetDeployer
/// @notice Script to deploy the FaucetDeployer contract on L1.
///         The FaucetDeployer is used by multisigs (via delegatecall) to deploy
///         and manage NativeAssetFaucet contracts on L2.
contract DeployFaucetDeployer is Script {
    /// @notice The CREATE2 Deployer predeploy address on L2
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    /// @notice Deploys the FaucetDeployer contract on L1.
    /// @param _portal The OptimismPortal2 contract address.
    function run(address _portal) public returns (FaucetDeployer) {
        console.log("=== DeployFaucetDeployer ===");
        console.log("Portal:", _portal);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);

        vm.startBroadcast();

        FaucetDeployer faucetDeployer = new FaucetDeployer(IOptimismPortal2(payable(_portal)), CREATE2_DEPLOYER);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("FaucetDeployer deployed at:", address(faucetDeployer));
        console.log("\nUsage:");
        console.log("1. From LiquidityController owner (Safe), delegatecall:");
        console.log("   faucetDeployer.deployAndAuthorize(faucetOwner, permissionlessAmount, gasLimit)");
        console.log("2. From faucet owner (Safe), delegatecall:");
        console.log("   faucetDeployer.mint(faucetAddress, recipient, amount, gasLimit)");

        return faucetDeployer;
    }
}
