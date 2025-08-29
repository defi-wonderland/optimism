// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Interfaces
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL2CrossDomainMessenger } from "interfaces/L2/IL2CrossDomainMessenger.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";

/// @title AuthDeposit
/// @notice Script to authorize a minter on L2 LiquidityController by sending a depositTransaction from L1
contract AuthDeposit is Script {
    // L1 contracts
    IOptimismPortal2 public optimismPortal;
    IL1CrossDomainMessenger public l1CrossDomainMessenger;

    // L2 contracts
    IL2CrossDomainMessenger public l2CrossDomainMessenger;

    // Config
    uint256 public l1Fork;
    uint256 public l2Fork;

    // LiquidityController address on L2
    address public liquidityController;

    function run() public {
        setUp();
        _authorizeMinter();
    }

    function setUp() public {
        l1Fork = vm.createFork("http://127.0.0.1:8544"); // chainId 900
        l2Fork = vm.createFork("http://127.0.0.1:8545"); // chainId 901

        vm.selectFork(l2Fork);
        l2CrossDomainMessenger = IL2CrossDomainMessenger(payable(0x4200000000000000000000000000000000000007));

        l1CrossDomainMessenger =
            IL1CrossDomainMessenger(payable(address(l2CrossDomainMessenger.l1CrossDomainMessenger())));
        liquidityController = Predeploys.LIQUIDITY_CONTROLLER;

        vm.selectFork(l1Fork);
        optimismPortal = IOptimismPortal2(payable(address(l1CrossDomainMessenger.portal())));
    }

    function _authorizeMinter() public {
        vm.selectFork(l2Fork);
        console.log("ProxyAdmin:", IProxyAdmin(Predeploys.PROXY_ADMIN).owner());
        console.log("msg.sender:", msg.sender);

        vm.selectFork(l1Fork);

        address minterToAuthorize = 0xe1Ba284CC77AD2FB7BC7C225d4A559B8D403Be32;
        console.log("Minter to authorize:", minterToAuthorize);

        // Send the deposit transaction with ProxyAdmin as the sender
        // This will execute authorizeMinter on L2 LiquidityController when processed
        vm.broadcast();
        optimismPortal.depositTransaction(
            liquidityController, // to
            0, // value
            200000, // gasLimit
            false, // isCreation
            abi.encodeCall(ILiquidityController.authorizeMinter, (minterToAuthorize)) // data
        );

        console.log("Deposit transaction sent to authorize minter:", minterToAuthorize);
    }
}
