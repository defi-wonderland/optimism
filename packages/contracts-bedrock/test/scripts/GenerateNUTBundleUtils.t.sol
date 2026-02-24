// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { Test } from "test/setup/Test.sol";

// Scripts
import { GenerateNUTBundleUtils } from "scripts/upgrade/GenerateNUTBundleUtils.sol";

// Libraries
import { Fork } from "scripts/libraries/Config.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Constants } from "src/libraries/Constants.sol";

// Interfaces
import { IProxy } from "interfaces/universal/IProxy.sol";

// Contracts
import { ConditionalDeployer } from "src/L2/ConditionalDeployer.sol";

/// @title GenerateNUTBundleUtils_TestInit
/// @notice Shared setup contract for GenerateNUTBundleUtils tests.
contract GenerateNUTBundleUtils_TestInit is Test {
    GenerateNUTBundleUtils utils;

    string constant TEST_UPGRADE_NAME = "jovian";

    function setUp() public virtual {
        utils = new GenerateNUTBundleUtils();
    }
}


/// @title GenerateNUTBundleUtils_GetPredeploysToUpgrade_Test
/// @notice Tests for getPredeploysToUpgrade function.
contract GenerateNUTBundleUtils_GetPredeploysToUpgrade_Test is GenerateNUTBundleUtils_TestInit {
    /// @notice Tests that getPredeploysToUpgrade returns correct count.
    function test_getPredeploysToUpgrade_succeeds() public {
        address[] memory predeploys = utils.getPredeploysToUpgrade();

        // Should have 25 predeploys: 21 base + 2 INTEROP + 2 CGT
        assertEq(predeploys.length, 25, "Should have 25 predeploys");

        // Verify INTEROP-specific predeploys are included
        bool hasCrossL2Inbox = false;
        bool hasL2ToL2CrossDomainMessenger = false;

        // Verify CGT-specific predeploys are included
        bool hasNativeAssetLiquidity = false;
        bool hasLiquidityController = false;

        for (uint256 i = 0; i < predeploys.length; i++) {
            if (predeploys[i] == Predeploys.CROSS_L2_INBOX) hasCrossL2Inbox = true;
            if (predeploys[i] == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) hasL2ToL2CrossDomainMessenger = true;
            if (predeploys[i] == Predeploys.NATIVE_ASSET_LIQUIDITY) hasNativeAssetLiquidity = true;
            if (predeploys[i] == Predeploys.LIQUIDITY_CONTROLLER) hasLiquidityController = true;
        }

        assertTrue(hasCrossL2Inbox, "Should include CrossL2Inbox");
        assertTrue(hasL2ToL2CrossDomainMessenger, "Should include L2ToL2CrossDomainMessenger");
        assertTrue(hasNativeAssetLiquidity, "Should include NativeAssetLiquidity");
        assertTrue(hasLiquidityController, "Should include LiquidityController");
    }

    /// @notice Tests that getPredeploysToUpgrade is deterministic on multiple calls.
    function test_getPredeploysToUpgrade_deterministic_succeeds() public {
        address[] memory predeploys1 = utils.getPredeploysToUpgrade();
        address[] memory predeploys2 = utils.getPredeploysToUpgrade();

        assertEq(predeploys1.length, predeploys2.length, "Should produce same number of predeploys");

        for (uint256 i = 0; i < predeploys1.length; i++) {
            assertEq(predeploys1[i], predeploys2[i], "Predeploy addresses should match");
        }
    }
}

/// @title GenerateNUTBundleUtils_ComputeCreate2Address_Test
/// @notice Tests for computeCreate2Address function.
contract GenerateNUTBundleUtils_ComputeCreate2Address_Test is GenerateNUTBundleUtils_TestInit {
    /// @notice Tests that computeCreate2Address produces correct address.
    function testFuzz_computeCreate2Address_succeeds(bytes32 _salt) public view {
        vm.assume(_salt != bytes32(0));
        bytes memory code = vm.getCode("StorageSetter.sol:StorageSetter");
        address computed = utils.computeCreate2Address(code, _salt);

        // Verify address is not zero
        assertNotEq(computed, address(0), "Computed address should not be zero");

        // Verify address is deterministic
        address computed2 = utils.computeCreate2Address(code, _salt);
        assertEq(computed, computed2, "Computed address should be deterministic");
    }

    /// @notice Tests that computeCreate2Address produces different addresses for different salts.
    function testFuzz_computeCreate2Address_differentSalts_succeeds(bytes32 _salt1, bytes32 _salt2) public view {
        vm.assume(_salt1 != bytes32(0));
        vm.assume(_salt2 != bytes32(0));
        vm.assume(_salt1 != _salt2);
        bytes memory code = vm.getCode("StorageSetter.sol:StorageSetter");

        address addr1 = utils.computeCreate2Address(code, _salt1);
        address addr2 = utils.computeCreate2Address(code, _salt2);

        assertNotEq(addr1, addr2, "Different salts should produce different addresses");
    }

    /// @notice Tests that computeCreate2Address produces different addresses for different code.
    function testFuzz_computeCreate2Address_differentCode_succeeds(bytes32 _salt) public view {
        vm.assume(_salt != bytes32(0));
        bytes memory code1 = vm.getCode("StorageSetter.sol:StorageSetter");
        bytes memory code2 = vm.getCode("L2CrossDomainMessenger.sol:L2CrossDomainMessenger");

        address addr1 = utils.computeCreate2Address(code1, _salt);
        address addr2 = utils.computeCreate2Address(code2, _salt);

        assertNotEq(addr1, addr2, "Different code should produce different addresses");
    }
}

/// @title GenerateNUTBundleUtils_CreateDeploymentTxn_Test
/// @notice Tests for createDeploymentTxn function.
contract GenerateNUTBundleUtils_CreateDeploymentTxn_Test is GenerateNUTBundleUtils_TestInit {
    /// @notice Tests that createDeploymentTxn produces correct transaction structure.
    function testFuzz_createDeploymentTxn_succeeds(bytes32 _salt, uint64 _gasLimit) public view {
        vm.assume(_salt != bytes32(0));
        vm.assume(_gasLimit > 0);
        NetworkUpgradeTxns.NetworkUpgradeTxn memory txn = utils.createDeploymentTxn(
            TEST_UPGRADE_NAME, "StorageSetter", "StorageSetter.sol:StorageSetter", _salt, _gasLimit
        );

        // Verify transaction fields
        assertEq(
            txn.intent,
            string.concat(TEST_UPGRADE_NAME, ": Deploy StorageSetter Implementation"),
            "Transaction intent should match"
        );
        assertEq(txn.from, Constants.DEPOSITOR_ACCOUNT, "Transaction from should be DEPOSITOR_ACCOUNT");
        assertEq(txn.to, Predeploys.CONDITIONAL_DEPLOYER, "Transaction to should be CONDITIONAL_DEPLOYER");
        assertEq(txn.gasLimit, _gasLimit, "Transaction gasLimit should match");
        assertGt(txn.data.length, 0, "Transaction data should not be empty");

        // Verify data is encoded correctly (should be ConditionalDeployer.deploy(salt, code))
        bytes memory code = vm.getCode("StorageSetter.sol:StorageSetter");
        bytes memory expectedData = abi.encodeCall(ConditionalDeployer.deploy, (_salt, code));
        assertEq(keccak256(txn.data), keccak256(expectedData), "Transaction data should be encoded correctly");
    }

    /// @notice Tests that transactions are deterministic for the same inputs.
    function testFuzz_createDeploymentTxn_deterministic_succeeds(bytes32 _salt, uint64 _gasLimit) public view {
        vm.assume(_salt != bytes32(0));
        vm.assume(_gasLimit > 0);
        NetworkUpgradeTxns.NetworkUpgradeTxn memory txn1 = utils.createDeploymentTxn(
            TEST_UPGRADE_NAME, "StorageSetter", "StorageSetter.sol:StorageSetter", _salt, _gasLimit
        );

        NetworkUpgradeTxns.NetworkUpgradeTxn memory txn2 = utils.createDeploymentTxn(
            TEST_UPGRADE_NAME, "StorageSetter", "StorageSetter.sol:StorageSetter", _salt, _gasLimit
        );

        // Verify all fields match
        assertEq(txn1.intent, txn2.intent, "intent should match");
        assertEq(txn1.from, txn2.from, "from should match");
        assertEq(txn1.to, txn2.to, "to should match");
        assertEq(txn1.gasLimit, txn2.gasLimit, "gasLimit should match");
        assertEq(keccak256(txn1.data), keccak256(txn2.data), "data should match");
    }
}

/// @title GenerateNUTBundleUtils_CreateDeploymentTxnWithArgs_Test
/// @notice Tests for createDeploymentTxnWithArgs function.
contract GenerateNUTBundleUtils_CreateDeploymentTxnWithArgs_Test is GenerateNUTBundleUtils_TestInit {
    /// @notice Tests that createDeploymentTxnWithArgs produces correct transaction structure.
    function testFuzz_createDeploymentTxnWithArgs_succeeds(bytes32 _salt, uint64 _gasLimit) public view {
        vm.assume(_salt != bytes32(0));
        vm.assume(_gasLimit > 0);
        bytes memory args = abi.encode(Predeploys.L2_ERC721_BRIDGE, uint256(1));

        NetworkUpgradeTxns.NetworkUpgradeTxn memory txn = utils.createDeploymentTxnWithArgs(
            TEST_UPGRADE_NAME,
            "OptimismMintableERC721Factory",
            "OptimismMintableERC721Factory.sol:OptimismMintableERC721Factory",
            args,
            _salt,
            _gasLimit
        );

        // Verify transaction fields
        assertEq(
            txn.intent,
            string.concat(TEST_UPGRADE_NAME, ": Deploy OptimismMintableERC721Factory Implementation"),
            "Transaction intent should match"
        );
        assertEq(txn.from, Constants.DEPOSITOR_ACCOUNT, "Transaction from should be DEPOSITOR_ACCOUNT");
        assertEq(txn.to, Predeploys.CONDITIONAL_DEPLOYER, "Transaction to should be CONDITIONAL_DEPLOYER");
        assertEq(txn.gasLimit, _gasLimit, "Transaction gasLimit should match");
        assertGt(txn.data.length, 0, "Transaction data should not be empty");

        // Verify data includes constructor args
        bytes memory code =
            abi.encodePacked(vm.getCode("OptimismMintableERC721Factory.sol:OptimismMintableERC721Factory"), args);
        bytes memory expectedData = abi.encodeCall(ConditionalDeployer.deploy, (_salt, code));
        assertEq(keccak256(txn.data), keccak256(expectedData), "Transaction data should include constructor args");
    }

    /// @notice Tests that createDeploymentTxnWithArgs with empty args equals createDeploymentTxn.
    function testFuzz_createDeploymentTxnWithArgs_emptyArgsEquivalence_succeeds(bytes32 _salt, uint64 _gasLimit)
        public
        view
    {
        vm.assume(_salt != bytes32(0));
        vm.assume(_gasLimit > 0);

        NetworkUpgradeTxns.NetworkUpgradeTxn memory txnWithArgs = utils.createDeploymentTxnWithArgs(
            TEST_UPGRADE_NAME, "StorageSetter", "StorageSetter.sol:StorageSetter", "", _salt, _gasLimit
        );

        NetworkUpgradeTxns.NetworkUpgradeTxn memory txnWithoutArgs = utils.createDeploymentTxn(
            TEST_UPGRADE_NAME, "StorageSetter", "StorageSetter.sol:StorageSetter", _salt, _gasLimit
        );

        // Verify all fields match
        assertEq(txnWithArgs.intent, txnWithoutArgs.intent, "intent should match");
        assertEq(txnWithArgs.from, txnWithoutArgs.from, "from should match");
        assertEq(txnWithArgs.to, txnWithoutArgs.to, "to should match");
        assertEq(txnWithArgs.gasLimit, txnWithoutArgs.gasLimit, "gasLimit should match");
        assertEq(keccak256(txnWithArgs.data), keccak256(txnWithoutArgs.data), "data should match");
    }
}

/// @title GenerateNUTBundleUtils_CreateUpgradeTxn_Test
/// @notice Tests for createUpgradeTxn function.
contract GenerateNUTBundleUtils_CreateUpgradeTxn_Test is GenerateNUTBundleUtils_TestInit {
    /// @notice Tests that createUpgradeTxn produces correct transaction structure.
    function testFuzz_createUpgradeTxn_succeeds(address _implementation, uint64 _gasLimit) public view {
        vm.assume(_implementation != address(0));
        vm.assume(_gasLimit > 0);

        NetworkUpgradeTxns.NetworkUpgradeTxn memory txn =
            utils.createUpgradeTxn(TEST_UPGRADE_NAME, "ProxyAdmin", Predeploys.PROXY_ADMIN, _implementation, _gasLimit);

        // Verify transaction fields
        assertEq(
            txn.intent,
            string.concat(TEST_UPGRADE_NAME, ": Upgrade ProxyAdmin Implementation"),
            "Transaction intent should match"
        );
        assertEq(txn.from, address(0), "Transaction from should be address(0) for proxy upgrade");
        assertEq(txn.to, Predeploys.PROXY_ADMIN, "Transaction to should be ProxyAdmin");
        assertEq(txn.gasLimit, _gasLimit, "Transaction gasLimit should match");
        assertGt(txn.data.length, 0, "Transaction data should not be empty");

        // Verify data is encoded correctly (should be IProxy.upgradeTo(implementation))
        bytes memory expectedData = abi.encodeCall(IProxy.upgradeTo, (_implementation));
        assertEq(keccak256(txn.data), keccak256(expectedData), "Transaction data should be encoded correctly");
    }
}
