// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Contracts
import { L1CGTBridge } from "src/L1/L1CGTBridge.sol";
import { L2CGTBridge } from "src/L2/L2CGTBridge.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { CGT } from "src/L1/CGT.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL2CrossDomainMessenger } from "interfaces/L2/IL2CrossDomainMessenger.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title DeployBridges
/// @notice Script to deploy L1CGTBridge and L2CGTBridge contracts
contract DeployBridges is Script {
    // L1 Contracts
    IL1CrossDomainMessenger public l1CrossDomainMessenger;
    ISuperchainConfig public superchainConfig;

    // L2 Contracts
    IL2CrossDomainMessenger public l2CrossDomainMessenger;
    ILiquidityController public liquidityController;

    // L1 RPC URL
    string constant L1_RPC_URL = "http://127.0.0.1:8544";
    // L2 RPC URL
    string constant L2_RPC_URL = "http://127.0.0.1:8545";

    // Fork IDs
    uint256 public l1Fork;
    uint256 public l2Fork;

    // Deployed contracts
    address public l1CGTBridge;
    address public l2CGTBridge;
    address public cgtToken;

    // Test user address
    address public testUser = makeAddr("testUser");

    function run() public {
        setUp();
        deployCGTToken();
        deployL1Bridge();
        deployL2Bridge();
        initializeBridges();
        mintAndLogBalances();

        console.log("=== Bridge Deployment Completed ===");
        console.log("L1CGTBridge deployed at:", l1CGTBridge);
        console.log("L2CGTBridge deployed at:", l2CGTBridge);
        console.log("CGT Token deployed at:", cgtToken);
    }

    function setUp() public {
        l1Fork = vm.createFork(L1_RPC_URL); // chainId 900
        l2Fork = vm.createFork(L2_RPC_URL); // chainId 901

        console.log("=== Bridge Deployment Started ===");
        console.log("L1 Fork ID:", l1Fork);
        console.log("L2 Fork ID:", l2Fork);
        console.log("Test user:", testUser);
        vm.selectFork(l2Fork);
        l2CrossDomainMessenger = IL2CrossDomainMessenger(payable(Predeploys.L2_CROSS_DOMAIN_MESSENGER));
        l1CrossDomainMessenger =
            IL1CrossDomainMessenger(payable(address(l2CrossDomainMessenger.l1CrossDomainMessenger())));

        vm.selectFork(l1Fork);
        superchainConfig = ISuperchainConfig(l1CrossDomainMessenger.superchainConfig());

        // Get LiquidityController (predeploy)
        liquidityController = ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER);
    }

    function deployCGTToken() public {
        vm.selectFork(l1Fork);
        console.log("--- Deploying CGT Token ---");

        vm.startBroadcast();

        // Deploy CGT token
        CGT cgt = new CGT();
        cgtToken = address(cgt);
        console.log("CGT Token deployed at:", cgtToken);

        vm.stopBroadcast();
    }

    function deployL1Bridge() public {
        vm.selectFork(l1Fork);
        console.log("--- Deploying L1CGTBridge ---");

        vm.startBroadcast();

        // Deploy implementation
        L1CGTBridge l1Implementation = new L1CGTBridge();
        console.log("L1CGTBridge implementation:", address(l1Implementation));

        // Deploy proxy
        Proxy l1Proxy = new Proxy(msg.sender);
        console.log("L1CGTBridge proxy:", address(l1Proxy));

        // Upgrade proxy to implementation
        l1Proxy.upgradeTo(address(l1Implementation));
        console.log("L1CGTBridge proxy upgraded to implementation");

        l1CGTBridge = address(l1Proxy);

        vm.stopBroadcast();
    }

    function deployL2Bridge() public {
        vm.selectFork(l2Fork);
        console.log("--- Deploying L2CGTBridge ---");

        vm.startBroadcast();

        // Deploy implementation
        L2CGTBridge l2Implementation = new L2CGTBridge();
        console.log("L2CGTBridge implementation:", address(l2Implementation));

        // Deploy proxy
        Proxy l2Proxy = new Proxy(msg.sender);
        console.log("L2CGTBridge proxy:", address(l2Proxy));

        // Upgrade proxy to implementation
        l2Proxy.upgradeTo(address(l2Implementation));
        console.log("L2CGTBridge proxy upgraded to implementation");

        l2CGTBridge = address(l2Proxy);

        vm.stopBroadcast();
    }

    function initializeBridges() public {
        // Initialize L1 Bridge
        vm.selectFork(l1Fork);
        console.log("--- Initializing L1CGTBridge ---");

        vm.startBroadcast();

        // Use deployed CGT token
        IERC20 cgt = IERC20(cgtToken);

        L1CGTBridge(l1CGTBridge).initialize(l1CrossDomainMessenger, superchainConfig, cgt, l2CGTBridge);

        console.log("L1CGTBridge initialized");

        vm.stopBroadcast();

        // Initialize L2 Bridge
        vm.selectFork(l2Fork);
        console.log("--- Initializing L2CGTBridge ---");

        vm.startBroadcast();

        L2CGTBridge(l2CGTBridge).initialize(l2CrossDomainMessenger, liquidityController, l1CGTBridge);

        console.log("L2CGTBridge initialized");

        vm.stopBroadcast();
    }

    function mintAndLogBalances() public {
        vm.selectFork(l1Fork);
        console.log("--- Minting CGT Tokens ---");

        vm.startBroadcast();

        // Mint 1,000,000 CGT tokens to the sender
        uint256 mintAmount = 1_000_000 ether;
        CGT(cgtToken).mint(msg.sender, mintAmount);
        console.log("Minted", mintAmount / 1e18, "CGT tokens to sender:", msg.sender);

        vm.stopBroadcast();

        // Log balances
        console.log("--- CGT Token Balances ---");
        uint256 senderBalance = CGT(cgtToken).balanceOf(msg.sender);
        uint256 totalSupply = CGT(cgtToken).totalSupply();

        console.log("Sender balance:", senderBalance / 1e18, "CGT");
        console.log("Total supply:", totalSupply / 1e18, "CGT");
    }
}
