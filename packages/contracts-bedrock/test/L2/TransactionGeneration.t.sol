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
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";

contract TransactionGenerationTest is Test {
    TransactionGeneration public transactionGeneration;
    bytes32 public immutable _salt = keccak256(abi.encode(Config.implSalt()));

    function setUp() public {
        vm.createSelectFork(Config.forkRpcUrl());
        transactionGeneration = new TransactionGeneration();

        // etch the L2ProxyAdmin
        vm.etch(Predeploys.PROXY_ADMIN, vm.getDeployedCode("ProxyAdmin.sol:ProxyAdmin"));
    }

    /// @notice Test that the upgrade transactions defined in the XForkContractsManager succeed.
    function test_upgradeTransactions_succeeds() public {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns = transactionGeneration.run("XForkContractsManager", _salt);

        // The test expects at least 3 transactions:
        // 1+ predeploy deployments
        // 1 L2ContractsManager deployment
        // 1 L2ContractsManager execution
        assertGe(txns.length, 3, "Should have at least 3 transactions");

        // Execute all transactions
        for (uint256 i = 0; i < txns.length; i++) {
            vm.prank(txns[i].from);
            (bool success,) = txns[i].to.call{ value: txns[i].value, gas: txns[i].gas }(txns[i].data);
            assertTrue(success, string.concat("Transaction ", vm.toString(i), " should succeed"));
        }

        // At this point the L1Block should have been upgraded to v1.8.0
        assertEq(L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).version(), "1.8.0");
    }

    /// @notice Test that the upgrade transaction structure is correct.
    function test_upgradeTransactions_transactionStructure_succeeds() public {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns = transactionGeneration.run("XForkContractsManager", _salt);

        // Verify we have at least 3 transactions
        assertGe(txns.length, 3, "Should have at least 3 transactions");

        // Last two transactions should be:
        // - Second to last: L2ContractsManager deployment via CREATE2
        // - Last: Execute upgrade via ProxyAdmin

        // Second to last transaction: L2ContractsManager deployment via CREATE2
        assertEq(txns[txns.length - 2].from, address(0), "L2ContractsManager deployment should be from address(0)");
        assertEq(txns[txns.length - 2].value, 0, "L2ContractsManager deployment should have 0 value");
        assertEq(txns[txns.length - 2].mint, 0, "L2ContractsManager deployment should have 0 mint");
        assertFalse(
            txns[txns.length - 2].isSystemTransaction, "L2ContractsManager deployment should not be a system tx"
        );

        // Last transaction: Execute upgrade via ProxyAdmin
        assertEq(txns[txns.length - 1].from, Constants.DEPOSITOR_ACCOUNT, "Execute should be from DEPOSITOR_ACCOUNT");
        assertEq(txns[txns.length - 1].to, Predeploys.PROXY_ADMIN, "Execute should target PROXY_ADMIN");
        assertEq(txns[txns.length - 1].value, 0, "Execute should have 0 value");
        assertEq(txns[txns.length - 1].mint, 0, "Execute should have 0 mint");
        assertFalse(txns[txns.length - 1].isSystemTransaction, "Execute should not be a system tx");

        // All predeploy deployment transactions (all except last 2) should follow the same pattern
        for (uint256 i = 0; i < txns.length - 2; i++) {
            assertEq(txns[i].from, address(0), "Predeploy deployment should be from address(0)");
            assertEq(txns[i].value, 0, "Predeploy deployment should have 0 value");
            assertEq(txns[i].mint, 0, "Predeploy deployment should have 0 mint");
            assertFalse(txns[i].isSystemTransaction, "Predeploy deployment should not be a system tx");
        }

        // Verify that the number of predeploy deployments matches the ProxyUpgrade array length
        uint256 predeployDeploymentCount = txns.length - 2;

        // Decode the last transaction's data to extract the ProxyUpgrade array
        // performDelegateCall(address _target, L2ContractsManager.ProxyUpgrade[] memory proxyUpgrades)
        bytes memory callData = txns[txns.length - 1].data;

        // Extract function selector (first 4 bytes)
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 32))
        }

        // Verify the function selector is correct
        assertEq(selector, bytes4(keccak256("performDelegateCall(address,(address,address)[])")));

        // Create new bytes array without selector for decoding
        bytes memory params = new bytes(callData.length - 4);
        for (uint256 i = 0; i < params.length; i++) {
            params[i] = callData[i + 4];
        }

        // Decode the parameters
        (, L2ContractsManager.ProxyUpgrade[] memory proxyUpgrades) =
            abi.decode(params, (address, L2ContractsManager.ProxyUpgrade[]));

        // Assert that counts match
        assertEq(
            predeployDeploymentCount,
            proxyUpgrades.length,
            "Number of predeploy deployments should match ProxyUpgrade array length"
        );
    }
}
