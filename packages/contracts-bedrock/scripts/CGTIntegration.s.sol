// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { INativeAssetLiquidity } from "interfaces/L2/INativeAssetLiquidity.sol";
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title CGTIntegration
/// @notice Script to simulate interactions on a CGT (Custom Gas Token) chain.
///         Demonstrates the functionality of LiquidityController, NativeAssetLiquidity,
///         L1Block with CGT support, and L2ToL1MessagePasser in CGT mode.
contract CGTIntegration is Script {
    // Contracts
    ILiquidityController public immutable liquidityController = ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER);
    INativeAssetLiquidity public immutable nativeAssetLiquidity =
        INativeAssetLiquidity(Predeploys.NATIVE_ASSET_LIQUIDITY);
    IL1Block public immutable l1Block = IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES);
    IL2ToL1MessagePasser public immutable l2ToL1MessagePasser =
        IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER));
    IProxyAdmin public immutable proxyAdmin = IProxyAdmin(Predeploys.PROXY_ADMIN);

    // Users
    address public testUser1 = makeAddr("testUser1");
    address public testUser2 = makeAddr("testUser2");
    address public testMinter = makeAddr("testMinter");

    // Events
    event MinterAuthorized(address indexed minter);
    event LiquidityMinted(address indexed minter, address indexed to, uint256 amount);
    event LiquidityBurned(address indexed burner, uint256 amount);

    function run() public {
        console.log("=== CGT Integration Script Started ===");

        _validateCGTMode();
        _simulateLiquidityControllerOperations();
        _simulateNativeAssetLiquidityOperations();
        _simulateL2ToL1MessagePasserCGTMode();

        console.log("=== CGT Integration Script Completed ===");
    }

    function _validateCGTMode() internal view {
        console.log("--- L1Block ---");

        vm.assertTrue(l1Block.isCustomGasToken());
        console.log("CGT enabled:", l1Block.isCustomGasToken());

        string memory tokenName = l1Block.gasPayingTokenName();
        string memory tokenSymbol = l1Block.gasPayingTokenSymbol();

        console.log("Gas Paying Token Name:", tokenName);
        console.log("Gas Paying Token Symbol:", tokenSymbol);
    }

    function _simulateLiquidityControllerOperations() internal {
        console.log("--- LiquidityController ---");
        // Authorize minter
        vm.startPrank(proxyAdmin.owner());

        vm.expectEmit(address(liquidityController));
        emit MinterAuthorized(testMinter);
        liquidityController.authorizeMinter(testMinter);

        vm.assertTrue(liquidityController.minters(testMinter));
        console.log("Minter authorized:", testMinter);
        vm.stopPrank();

        // Mint
        vm.startPrank(testMinter);
        uint256 prevNativeAssetLiquidityBalance = address(nativeAssetLiquidity).balance;
        uint256 prevUserBalance = testUser1.balance;
        uint256 mintAmount = 1000 ether;

        vm.expectCall(address(nativeAssetLiquidity), abi.encodeCall(INativeAssetLiquidity.withdraw, (mintAmount)));
        vm.expectEmit(address(liquidityController));
        emit LiquidityMinted(testMinter, testUser1, mintAmount);
        liquidityController.mint(testUser1, mintAmount);

        vm.assertEq(prevNativeAssetLiquidityBalance - mintAmount, address(nativeAssetLiquidity).balance);
        vm.assertEq(prevUserBalance + mintAmount, testUser1.balance);
        console.log("Minted", testUser1.balance, "tokens to", testUser1);

        // Burn
        uint256 burnAmount = 500 ether;
        vm.deal(testMinter, burnAmount);
        prevUserBalance = testMinter.balance;
        prevNativeAssetLiquidityBalance = address(nativeAssetLiquidity).balance;

        vm.expectCall(address(nativeAssetLiquidity), burnAmount, abi.encodeCall(INativeAssetLiquidity.deposit, ()));
        vm.expectEmit(address(liquidityController));
        emit LiquidityBurned(testMinter, burnAmount);
        liquidityController.burn{ value: burnAmount }();

        vm.assertEq(prevUserBalance - burnAmount, testMinter.balance);
        vm.assertEq(prevNativeAssetLiquidityBalance + burnAmount, address(nativeAssetLiquidity).balance);
        console.log("Minter burned", burnAmount, "tokens");

        vm.stopPrank();
    }

    function _simulateNativeAssetLiquidityOperations() internal {
        console.log("--- NativeAssetLiquidity ---");

        // Unauthorized deposit
        vm.deal(testUser1, 1000 ether);
        vm.startPrank(testUser1);
        vm.expectRevert(abi.encodeWithSelector(INativeAssetLiquidity.Unauthorized.selector));
        nativeAssetLiquidity.deposit{ value: 100 ether }();
        vm.stopPrank();
        console.log("Unauthorized deposit reverted as expected");
    }

    function _simulateL2ToL1MessagePasserCGTMode() internal {
        console.log("--- L2ToL1MessagePasser ---");

        vm.startPrank(testUser1);

        address target = address(0x1234567890123456789012345678901234567890);
        uint256 gasLimit = 100000;
        bytes memory data = "test withdrawal data";

        // Test withdrawal with zero value (should succeed)
        uint256 nonceBefore = l2ToL1MessagePasser.messageNonce();
        console.log("Current L2ToL1MessagePasser message nonce:", nonceBefore);
        l2ToL1MessagePasser.initiateWithdrawal{ value: 0 }(target, gasLimit, data);
        vm.assertEq(l2ToL1MessagePasser.messageNonce(), nonceBefore + 1);

        console.log("Current L2ToL1MessagePasser message nonce:", l2ToL1MessagePasser.messageNonce());
        console.log("Initiated withdrawal with zero value succeeded");
        console.log("---");

        // Test withdrawal with non-zero value (should revert)
        vm.deal(testUser1, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IL2ToL1MessagePasser.NotAllowedOnCGTMode.selector));
        l2ToL1MessagePasser.initiateWithdrawal{ value: 1 ether }(target, gasLimit, data);

        vm.assertEq(l2ToL1MessagePasser.messageNonce(), nonceBefore + 1);
        console.log("Current L2ToL1MessagePasser message nonce:", l2ToL1MessagePasser.messageNonce());

        console.log("Initiated withdrawal with non-zero value reverted");

        vm.stopPrank();
    }
}
