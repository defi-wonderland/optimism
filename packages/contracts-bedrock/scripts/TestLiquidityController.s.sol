// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title TestLiquidityController
/// @notice Script to test the LiquidityController contract
contract TestLiquidityController is Script {
    uint256 private constant L2_PROXY_ADMIN_OWNER_PK =
        0xc24de1e962c31c8341cdae2b25b3e435d374b433a429d42c8c2398af1ffca3f9;
    uint256 private constant MINTER_PK = 0xd9fb56b9574ed61ab0478a607166eeb3a80b1b91ab1bf00f45932105d07b5e11;
    address private constant MINTER = 0x5D284fe6D6AEb73857960a0D041CF394b1198392;

    function run() external {
        address liquidityControllerAddress = Predeploys.LIQUIDITY_CONTROLLER;

        console.log("=== LiquidityController Test ===");
        console.log("LiquidityController Predeploy Address:", liquidityControllerAddress);

        // Check if the LiquidityController contract is deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(liquidityControllerAddress)
        }

        if (codeSize == 0) {
            console.log("Status: LiquidityController not found");
            return;
        }

        address MINT_BURN_PRECOMPILE = ILiquidityController(liquidityControllerAddress).MINT_BURN_PRECOMPILE();
        console.log("MINT_BURN_PRECOMPILE:", MINT_BURN_PRECOMPILE);

        console.log("LiquidityController contract found (code size:", codeSize, "bytes)");

        bool isMinter = ILiquidityController(liquidityControllerAddress).minters(MINTER);
        console.log("Is minter:", isMinter);

        vm.startBroadcast(L2_PROXY_ADMIN_OWNER_PK);
        ILiquidityController(liquidityControllerAddress).authorizeMinter(MINTER);
        vm.stopBroadcast();
        isMinter = ILiquidityController(liquidityControllerAddress).minters(MINTER);
        console.log("Is minter:", isMinter);

        console.log("MINTER:", MINTER);
        console.log("Balance:", address(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000).balance);
        vm.startBroadcast(MINTER_PK);
        ILiquidityController(liquidityControllerAddress).mint(address(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000), 1);
        vm.stopBroadcast();
        console.log("Balance:", address(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000).balance);
    }
}
