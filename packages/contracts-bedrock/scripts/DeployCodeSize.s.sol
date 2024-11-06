// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import "forge-std/Test.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";

interface ISharedLockbox {
    function unlockETH(uint256 _value) external;
}

interface IPortal {
    function migrateETH() external;
    function sharedLockbox() external view returns (address);
}

contract DeployCodeSize is Script {
    function run() public {
        // Deploy SuperchainTokenBridge
        vm.startBroadcast();
        address _portal = address(new OptimismPortalInterop(1, 2));
        console.log("OptimismPortalInterop: %s", address(_portal));
        console.log("OptimismPortalInterop size: %s", address(_portal).code.length);
        // console.log("shared locbkoxs: ", IPortal(_portal).sharedLockbox());
        // IPortal(_portal).migrateETH();
        // console.log("migrate eth call data 2: %s");
    }
}
