// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { TransactionGeneration } from "scripts/deploy/TransactionGeneration.s.sol";
import { Config } from "scripts/libraries/Config.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { Constants } from "src/libraries/Constants.sol";
import { XForkContractsManager } from "src/L2/XForkContractsManager.sol";

contract TransactionGenerationTest is Test {
    TransactionGeneration public transactionGeneration;

    function setUp() public {
        vm.createSelectFork(Config.forkRpcUrl(), Config.forkBlockNumber());
        transactionGeneration = new TransactionGeneration();

        // etch the L2ProxyAdmin
        vm.etch(Predeploys.PROXY_ADMIN, vm.getDeployedCode("ProxyAdmin.sol:ProxyAdmin"));
    }

    /// @notice Test that the upgrade transaction upgrading L1Block defined in the XForkContractsManager succeed.
    function test_upgradeTransactions_succeeds() public {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns = transactionGeneration.run("XForkContractsManager");

        // 1. L1Block Deployment
        // 2. L2ContractsManager Deployment
        // 3. L2ContractsManager Execute
        assertEq(txns.length, 3);

        for (uint256 i = 0; i < txns.length; i++) {
            vm.prank(txns[i].from);
            (bool success,) = txns[i].to.call{ value: txns[i].value, gas: txns[i].gas }(txns[i].data);
            assertTrue(success);
        }

        // At this point the L1Block should have been upgraded to v1.8.0
        assertEq(L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).version(), "1.8.0");
    }

    /// @notice Test that the upgrade transaction structure is correct.
    function test_upgradeTransactions_transactionStructure_succeeds() public {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns = transactionGeneration.run("XForkContractsManager");

        // Verify transaction structure
        assertEq(txns.length, 3);

        // First transaction: L1Block deployment via CREATE2
        assertEq(txns[0].from, address(0));
        assertEq(txns[0].value, 0);
        assertEq(txns[0].mint, 0);
        assertFalse(txns[0].isSystemTransaction);

        // Second transaction: L2ContractsManager deployment via CREATE2
        assertEq(txns[1].from, address(0));
        assertEq(txns[1].value, 0);
        assertEq(txns[1].mint, 0);
        assertFalse(txns[1].isSystemTransaction);

        // Third transaction: Execute upgrade via ProxyAdmin
        assertEq(txns[2].from, Constants.DEPOSITOR_ACCOUNT);
        assertEq(txns[2].to, Predeploys.PROXY_ADMIN);
        assertEq(txns[2].value, 0);
        assertEq(txns[2].mint, 0);
        assertFalse(txns[2].isSystemTransaction);
    }
}
