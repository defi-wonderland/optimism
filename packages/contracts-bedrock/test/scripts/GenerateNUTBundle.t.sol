// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { Test } from "test/setup/Test.sol";

// Scripts
import { GenerateNUTBundle } from "scripts/upgrade/GenerateNUTBundle.s.sol";

// Libraries
import { Fork } from "scripts/libraries/Config.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";

/// @title GenerateNUTBundleTest
/// @notice Tests that GenerateNUTBundle correctly generates Network Upgrade Transaction bundles
///         for L2 hardfork upgrades.
contract GenerateNUTBundleTest is Test {
    GenerateNUTBundle script;
    GenerateNUTBundle.Input input;

    uint256 constant TEST_L1_CHAIN_ID = 1;

    function setUp() public {
        script = new GenerateNUTBundle();
        script.setUp();

        _setDefaultInput();
    }

    function _setDefaultInput() internal {
        input = GenerateNUTBundle.Input({ l1ChainID: TEST_L1_CHAIN_ID });
    }

    /// @notice Tests that run succeeds.
    function test_run_succeeds() public {
        GenerateNUTBundle.Output memory output = script.run(input);

        NetworkUpgradeTxns.writeArtifact(output.txns, "deployments/nut-upgrade-test.json");
    }

    /// @notice Tests that run reverts with zero l1ChainID.
    function test_run_zeroL1ChainID_reverts() public {
        input.l1ChainID = 0;

        vm.expectRevert("GenerateNUTBundle: l1ChainID cannot be zero");
        script.run(input);
    }

    /// @notice Tests that transactions have correct structure.
    /// @dev Includes ConditionalDeployer and ProxyAdmin upgrades.
    function test_run_transactionStructure_succeeds() public {
        GenerateNUTBundle.Output memory output = script.run(input);

        // Should include:
        // 1. ConditionalDeployer deployment
        // 2. ConditionalDeployer upgrade
        // 3. All implementation deployments (StorageSetter + predeploys)
        // 4. ProxyAdmin upgrade
        // 5. L2ContractsManager deployment (TODO)
        // 6. Upgrade execution (TODO)

        // Verify first transaction intent corresponds to ConditionalDeployer deployment
        assertEq(
            output.txns[0].intent,
            "jovian: ConditionalDeployer Deployment",
            "First transaction should be ConditionalDeployer deployment"
        );

        assertEq(
            output.txns[1].intent,
            "jovian: Upgrade ConditionalDeployer Implementation",
            "Second transaction should be ConditionalDeployer upgrade"
        );

        /// TODO: Verify remaining transactions
    }

    /// @notice Tests that multiple runs produce deterministic results.
    function test_run_deterministicOutput_succeeds() public {
        GenerateNUTBundle.Output memory output1 = script.run(input);
        GenerateNUTBundle.Output memory output2 = script.run(input);

        // Verify same number of transactions
        assertEq(output1.txns.length, output2.txns.length, "Should produce same number of transactions");

        _compareTransactions(output1, output2);
    }

    function _compareTransactions(
        GenerateNUTBundle.Output memory _output1,
        GenerateNUTBundle.Output memory _output2
    )
        internal
        pure
    {
        assertEq(_output1.txns.length, _output2.txns.length, "Should produce same number of transactions");
        for (uint256 i = 0; i < _output1.txns.length; i++) {
            assertEq(_output1.txns[i].intent, _output2.txns[i].intent, "Transaction intent should match");
            assertEq(_output1.txns[i].from, _output2.txns[i].from, "Transaction from should match");
            assertEq(_output1.txns[i].to, _output2.txns[i].to, "Transaction to should match");
            assertEq(_output1.txns[i].gasLimit, _output2.txns[i].gasLimit, "Transaction gasLimit should match");
            assertEq(
                keccak256(_output1.txns[i].data), keccak256(_output2.txns[i].data), "Transaction data should match"
            );
        }
    }
}
