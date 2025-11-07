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

    /// @notice Address where L2ImplementationsDeployer is etched
    address constant L2_IMPLEMENTATIONS_DEPLOYER = 0x4200000000000000000000000000000000000420;

    function setUp() public {
        vm.createSelectFork(Config.forkRpcUrl());
        transactionGeneration = new TransactionGeneration();

        // etch the L2ProxyAdmin
        vm.etch(Predeploys.PROXY_ADMIN, vm.getDeployedCode("ProxyAdmin.sol:ProxyAdmin"));

        // etch the L2ImplementationsDeployer
        vm.etch(
            L2_IMPLEMENTATIONS_DEPLOYER, vm.getDeployedCode("L2ImplementationsDeployer.sol:L2ImplementationsDeployer")
        );
    }

    function _getInput() internal view returns (TransactionGeneration.Input memory) {
        return TransactionGeneration.Input({
            l2ChainID: block.chainid,
            l1ChainID: 1,
            l1CrossDomainMessengerProxy: payable(0x42000000000000000000000000000000000000F9),
            l1StandardBridgeProxy: payable(0x42000000000000000000000000000000000000f8),
            l1ERC721BridgeProxy: payable(0x4200000000000000000000000000000000000060),
            opChainProxyAdminOwner: 0x0000000000000000000000000000000000000222,
            sequencerFeeVaultRecipient: 0x42000000000000000000000000000000000000F7,
            sequencerFeeVaultMinimumWithdrawalAmount: 0x8ac7230489e80000,
            sequencerFeeVaultWithdrawalNetwork: 1,
            baseFeeVaultRecipient: 0x42000000000000000000000000000000000000f5,
            baseFeeVaultMinimumWithdrawalAmount: 0x8ac7230489e80000,
            baseFeeVaultWithdrawalNetwork: 0,
            l1FeeVaultRecipient: 0x42000000000000000000000000000000000000f6,
            l1FeeVaultMinimumWithdrawalAmount: 0x8ac7230489e80000,
            l1FeeVaultWithdrawalNetwork: 1,
            l2ImplDeployerAddress: L2_IMPLEMENTATIONS_DEPLOYER,
            l2cmName: "XForkContractsManager"
        });
    }

    /// @notice Test that the upgrade transactions defined in the XForkContractsManager succeed.
    function test_upgradeTransactions_succeeds() public {
        TransactionGeneration.Output memory output = transactionGeneration.run(_getInput());

        // The test expects at least 3 transactions:
        // 1+ predeploy deployments
        // 1 L2ContractsManager deployment
        // 1 L2ContractsManager execution
        assertGe(output.txns.length, 3, "Should have at least 3 transactions");

        // Execute all transactions
        for (uint256 i = 0; i < output.txns.length; i++) {
            vm.prank(output.txns[i].from);
            (bool success,) =
                output.txns[i].to.call{ value: output.txns[i].value, gas: output.txns[i].gas }(output.txns[i].data);
            assertTrue(success, string.concat("Transaction ", vm.toString(i), " should succeed"));
        }

        // At this point the L1Block should have been upgraded to v1.8.0
        assertEq(L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).version(), "1.8.0");
    }

    /// @notice Test that the upgrade transaction structure is correct.
    function test_upgradeTransactions_transactionStructure_succeeds() public {
        TransactionGeneration.Output memory output = transactionGeneration.run(_getInput());

        // Verify we have at least 3 transactions
        assertGe(output.txns.length, 3, "Should have at least 3 transactions");

        _verifyL2CMDeployment(output.txns);
        _verifyExecuteTransaction(output.txns);
        _verifyPredeployTransactions(output.txns);
        _verifyProxyUpgradesMatch(output.txns);
    }

    function _verifyL2CMDeployment(NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns) internal pure {
        // Second to last transaction: L2ContractsManager deployment via CREATE2
        uint256 l2cmIndex = txns.length - 2;
        assertEq(txns[l2cmIndex].from, address(0), "L2ContractsManager deployment should be from address(0)");
        assertEq(txns[l2cmIndex].value, 0, "L2ContractsManager deployment should have 0 value");
        assertEq(txns[l2cmIndex].mint, 0, "L2ContractsManager deployment should have 0 mint");
        assertFalse(txns[l2cmIndex].isSystemTransaction, "L2ContractsManager deployment should not be a system tx");
    }

    function _verifyExecuteTransaction(NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns) internal pure {
        // Last transaction: Execute upgrade via ProxyAdmin
        uint256 lastIndex = txns.length - 1;
        assertEq(txns[lastIndex].from, Constants.DEPOSITOR_ACCOUNT, "Execute should be from DEPOSITOR_ACCOUNT");
        assertEq(txns[lastIndex].to, Predeploys.PROXY_ADMIN, "Execute should target PROXY_ADMIN");
        assertEq(txns[lastIndex].value, 0, "Execute should have 0 value");
        assertEq(txns[lastIndex].mint, 0, "Execute should have 0 mint");
        assertFalse(txns[lastIndex].isSystemTransaction, "Execute should not be a system tx");
    }

    function _verifyPredeployTransactions(NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns) internal pure {
        // All predeploy deployment transactions (all except last 2) should follow the same pattern
        // Index 0 to length-3: Predeploy deployments
        // Index length-2: L2ContractsManager deployment
        // Index length-1: Execute transaction
        for (uint256 i = 0; i < txns.length - 2; i++) {
            assertEq(txns[i].from, address(0), "Predeploy deployment should be from address(0)");
            assertEq(txns[i].value, 0, "Predeploy deployment should have 0 value");
            assertEq(txns[i].mint, 0, "Predeploy deployment should have 0 mint");
            assertFalse(txns[i].isSystemTransaction, "Predeploy deployment should not be a system tx");
        }
    }

    function _verifyProxyUpgradesMatch(NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns) internal pure {
        bytes memory callData = txns[txns.length - 1].data;

        // Extract function selector (first 4 bytes)
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 32))
        }

        // Verify the function selector is correct
        assertEq(selector, bytes4(keccak256("performDelegateCall(address,(address,address)[])")));

        // Decode the parameters
        (, L2ContractsManager.ProxyUpgrade[] memory proxyUpgrades) = _decodeProxyUpgrades(callData);

        // Assert that counts match (subtract 2: L2ContractsManager, Execute)
        assertEq(
            txns.length - 2,
            proxyUpgrades.length,
            "Number of predeploy deployments should match ProxyUpgrade array length"
        );
    }

    function _decodeProxyUpgrades(bytes memory callData)
        internal
        pure
        returns (address, L2ContractsManager.ProxyUpgrade[] memory)
    {
        // Create new bytes array without selector for decoding
        bytes memory params = new bytes(callData.length - 4);
        for (uint256 i = 0; i < params.length; i++) {
            params[i] = callData[i + 4];
        }

        return abi.decode(params, (address, L2ContractsManager.ProxyUpgrade[]));
    }
}
