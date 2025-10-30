// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IGasPriceOracle } from "interfaces/L2/IGasPriceOracle.sol";

// Testing
import { Test } from "forge-std/Test.sol";

// Libraries
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title NetworkUpgradeTxns_TestInit
/// @notice Reusable test initialization for `NetworkUpgradeTxns` tests.
abstract contract NetworkUpgradeTxns_TestInit is Test {
    // Test constants matching Go implementation
    address constant L1_BLOCK_DEPLOYER = 0x4210000000000000000000000000000000000000;
    address constant GAS_PRICE_ORACLE_DEPLOYER = 0x4210000000000000000000000000000000000001;
    address constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    // Known source hashes from Ecotone upgrade (ecotone_upgrade_transactions_test.go:14-45)
    bytes32 constant DEPLOY_L1_BLOCK_HASH = 0x877a6077205782ea15a6dc8699fa5ebcec5e0f4389f09cb8eda09488231346f8;
    bytes32 constant DEPLOY_GAS_PRICE_ORACLE_HASH = 0xa312b4510adf943510f05fcc8f15f86995a5066bd83ce11384688ae20e6ecf42;
    bytes32 constant UPDATE_L1_BLOCK_PROXY_HASH = 0x18acb38c5ff1c238a7460ebc1b421fa49ec4874bdf1e0a530d234104e5e67dbc;
    bytes32 constant UPDATE_GAS_PRICE_ORACLE_HASH = 0xee4f9385eceef498af0be7ec5862229f426dec41c8d42397c7257a5117d9230a;
    bytes32 constant ENABLE_ECOTONE_HASH = 0x0c1cb38e99dbc9cbfab3bb80863380b0905290b37eb3d6ab18dc01c1f3e75f93;
    bytes32 constant BEACON_ROOTS_HASH = 0x69b763c48478b9dc2f65ada09b3d92133ec592ea715ec65ad6e7f3dc519dc00c;

    // Intent strings from Ecotone upgrade (ecotone_upgrade_transactions.go:27-32)
    string constant INTENT_DEPLOY_L1_BLOCK = "Ecotone: L1 Block Deployment";
    string constant INTENT_DEPLOY_GAS_PRICE_ORACLE = "Ecotone: Gas Price Oracle Deployment";
    string constant INTENT_UPDATE_L1_BLOCK_PROXY = "Ecotone: L1 Block Proxy Update";
    string constant INTENT_UPDATE_GAS_PRICE_ORACLE = "Ecotone: Gas Price Oracle Proxy Update";
    string constant INTENT_ENABLE_ECOTONE = "Ecotone: Gas Price Oracle Set Ecotone";
    string constant INTENT_BEACON_ROOTS = "Ecotone: beacon block roots contract deployment";
}

/// @title NetworkUpgradeTxns_SourceHash_Test
/// @notice Tests the `sourceHash` function matches Go implementation.
contract NetworkUpgradeTxns_SourceHash_Test is NetworkUpgradeTxns_TestInit {
    /// @notice Test sourceHash for L1Block deployment matches Go test vector
    function test_sourceHash_deployL1Block_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_DEPLOY_L1_BLOCK);
        assertEq(hash, DEPLOY_L1_BLOCK_HASH, "L1Block deployment hash mismatch");
    }

    /// @notice Test sourceHash for GasPriceOracle deployment matches Go test vector
    function test_sourceHash_deployGasPriceOracle_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_DEPLOY_GAS_PRICE_ORACLE);
        assertEq(hash, DEPLOY_GAS_PRICE_ORACLE_HASH, "GasPriceOracle deployment hash mismatch");
    }

    /// @notice Test sourceHash for L1Block proxy update matches Go test vector
    function test_sourceHash_updateL1BlockProxy_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_UPDATE_L1_BLOCK_PROXY);
        assertEq(hash, UPDATE_L1_BLOCK_PROXY_HASH, "L1Block proxy update hash mismatch");
    }

    /// @notice Test sourceHash for GasPriceOracle proxy update matches Go test vector
    function test_sourceHash_updateGasPriceOracleProxy_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_UPDATE_GAS_PRICE_ORACLE);
        assertEq(hash, UPDATE_GAS_PRICE_ORACLE_HASH, "GasPriceOracle proxy update hash mismatch");
    }

    /// @notice Test sourceHash for enable Ecotone matches Go test vector
    function test_sourceHash_enableEcotone_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_ENABLE_ECOTONE);
        assertEq(hash, ENABLE_ECOTONE_HASH, "Enable Ecotone hash mismatch");
    }

    /// @notice Test sourceHash for beacon roots matches Go test vector
    function test_sourceHash_beaconRoots_succeeds() public pure {
        bytes32 hash = NetworkUpgradeTxns.sourceHash(INTENT_BEACON_ROOTS);
        assertEq(hash, BEACON_ROOTS_HASH, "Beacon roots hash mismatch");
    }
}

/// @title NetworkUpgradeTxns_NewTx_Test
/// @notice Tests the `newTx` function.
contract NetworkUpgradeTxns_NewTx_Test is NetworkUpgradeTxns_TestInit {
    /// @notice Test newTx creates transaction with correct fields
    function test_newTx_allFields_succeeds(
        string memory _intent,
        address _from,
        address _to,
        uint256 _mint,
        uint256 _value,
        uint64 _gas,
        bool _isSystemTransaction,
        bytes memory _data
    )
        public
        pure
    {
        NetworkUpgradeTxns.UpgradeTxn memory txn = NetworkUpgradeTxns.newTx({
            intent: _intent,
            from: _from,
            to: _to,
            mint: _mint,
            value: _value,
            gas: _gas,
            isSystemTransaction: _isSystemTransaction,
            data: _data
        });

        assertEq(txn.sourceHash, NetworkUpgradeTxns.sourceHash(_intent), "sourceHash mismatch");
        assertEq(txn.from, _from, "from mismatch");
        assertEq(txn.to, _to, "to mismatch");
        assertEq(txn.mint, _mint, "mint mismatch");
        assertEq(txn.value, _value, "value mismatch");
        assertEq(txn.gas, _gas, "gas mismatch");
        assertEq(txn.isSystemTransaction, _isSystemTransaction, "isSystemTransaction mismatch");
        assertEq(txn.data, _data, "data mismatch");
    }
}

/// @title NetworkUpgradeTxns_NewDeploymentTx_Test
/// @notice Tests the `newDeploymentTx` function.
contract NetworkUpgradeTxns_NewDeploymentTx_Test is NetworkUpgradeTxns_TestInit {
    /// @notice Test newDeploymentTx creates correct deployment transaction
    function test_newDeploymentTx_succeeds(string memory _intent, address _from, uint64 _gas) public view {
        NetworkUpgradeTxns.UpgradeTxn memory txn = NetworkUpgradeTxns.newDeploymentTx({
            intent: _intent,
            from: _from,
            gas: _gas,
            forgeArtifactPath: "GasPriceOracle.sol:GasPriceOracle"
        });

        assertEq(txn.sourceHash, NetworkUpgradeTxns.sourceHash(_intent), "sourceHash mismatch");
        assertEq(txn.from, _from, "from mismatch");
        assertEq(txn.to, address(0), "to should be zero for deployment");
        assertEq(txn.mint, 0, "mint should be zero");
        assertEq(txn.value, 0, "value should be zero");
        assertEq(txn.gas, _gas, "gas mismatch");
        assertFalse(txn.isSystemTransaction, "should not be system transaction");
        assertTrue(txn.data.length > 0, "data should not be empty");
    }
}

/// @title NetworkUpgradeTxns_WriteArtifact_Test
/// @notice Tests the `writeArtifact` function.
contract NetworkUpgradeTxns_WriteArtifact_Test is NetworkUpgradeTxns_TestInit {
    /// @notice Test writeArtifact with empty array
    function test_writeArtifact_emptyArray() public {
        NetworkUpgradeTxns.UpgradeTxn[] memory txns = new NetworkUpgradeTxns.UpgradeTxn[](0);
        string memory outputPath = "deployments/nut-test-empty.json";
        NetworkUpgradeTxns.writeArtifact(txns, outputPath);
    }

    /// @notice Test writeArtifact with single Predeploy deployment
    function test_writeArtifact_singleDeployment() public {
        NetworkUpgradeTxns.UpgradeTxn[] memory txns = new NetworkUpgradeTxns.UpgradeTxn[](1);
        txns[0] = NetworkUpgradeTxns.newDeploymentTx({
            intent: INTENT_DEPLOY_L1_BLOCK,
            from: L1_BLOCK_DEPLOYER,
            gas: 375_000,
            forgeArtifactPath: "L1Block.sol:L1Block"
        });
        string memory outputPath = "deployments/nut-test-single.json";
        NetworkUpgradeTxns.writeArtifact(txns, outputPath);
    }

    /// @notice Test writeArtifact creates valid JSON file
    function test_writeArtifact_succeeds() public {
        NetworkUpgradeTxns.UpgradeTxn[] memory txns = new NetworkUpgradeTxns.UpgradeTxn[](2);

        txns[0] = NetworkUpgradeTxns.newDeploymentTx({
            intent: INTENT_DEPLOY_L1_BLOCK,
            from: L1_BLOCK_DEPLOYER,
            gas: 375_000,
            forgeArtifactPath: "L1Block.sol:L1Block"
        });

        txns[1] = NetworkUpgradeTxns.newTx({
            intent: INTENT_ENABLE_ECOTONE,
            from: DEPOSITOR_ACCOUNT,
            to: Predeploys.GAS_PRICE_ORACLE,
            mint: 0,
            value: 0,
            gas: 50_000,
            isSystemTransaction: false,
            data: abi.encodeCall(IGasPriceOracle.setEcotone, ())
        });

        string memory outputPath = "deployments/nut-test.json";
        NetworkUpgradeTxns.writeArtifact(txns, outputPath);
    }
}
