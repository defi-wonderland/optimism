// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { XForkContractsManager } from "src/L2/XForkContractsManager.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title XForkContractsManager_TestInit
/// @notice Initializes `xForkContractsManager` for testing.
contract XForkContractsManager_TestInit is Test {
    XForkContractsManager internal xForkContractsManager;

    function setUp() public {
        xForkContractsManager = new XForkContractsManager(_getInput());
    }

    function _getInput() internal returns (XForkContractsManager.Input memory) {
        return XForkContractsManager.Input({
            legacyMessagePasserImplementation: makeAddr("legacyMessagePasserImplementation"),
            deployerWhitelistImplementation: makeAddr("deployerWhitelistImplementation"),
            l2CrossDomainMessengerImplementation: makeAddr("l2CrossDomainMessengerImplementation"),
            gasPriceOracleImplementation: makeAddr("gasPriceOracleImplementation"),
            l2StandardBridgeImplementation: makeAddr("l2StandardBridgeImplementation"),
            sequencerFeeWalletImplementation: makeAddr("sequencerFeeWalletImplementation"),
            optimismMintableERC20FactoryImplementation: makeAddr("optimismMintableERC20FactoryImplementation"),
            l1BlockNumberImplementation: makeAddr("l1BlockNumberImplementation"),
            l2ERC721BridgeImplementation: makeAddr("l2ERC721BridgeImplementation"),
            l1BlockAttributesImplementation: makeAddr("l1BlockAttributesImplementation"),
            l2ToL1MessagePasserImplementation: makeAddr("l2ToL1MessagePasserImplementation"),
            optimismMintableERC721FactoryImplementation: makeAddr("optimismMintableERC721FactoryImplementation"),
            baseFeeVaultImplementation: makeAddr("baseFeeVaultImplementation"),
            l1FeeVaultImplementation: makeAddr("l1FeeVaultImplementation"),
            operatorFeeVaultImplementation: makeAddr("operatorFeeVaultImplementation"),
            schemaRegistryImplementation: makeAddr("schemaRegistryImplementation"),
            easImplementation: makeAddr("easImplementation")
        });
    }
}

/// @title XForkContractsManager_Constructor_Test
/// @notice Tests the constructor of the `XForkContractsManager` contract.
contract XForkContractsManager_Constructor_Test is XForkContractsManager_TestInit {
    /// @notice Tests that the constructor sets the implementation addresses correctly.
    function test_constructor_succeeds() external {
        XForkContractsManager.Input memory input = _getInput();

        assertEq(xForkContractsManager.LEGACY_MESSAGE_PASSER_IMPLEMENTATION(), input.legacyMessagePasserImplementation);
        assertEq(xForkContractsManager.DEPLOYER_WHITELIST_IMPLEMENTATION(), input.deployerWhitelistImplementation);
        assertEq(
            xForkContractsManager.L2_CROSS_DOMAIN_MESSENGER_IMPLEMENTATION(), input.l2CrossDomainMessengerImplementation
        );
        assertEq(xForkContractsManager.GAS_PRICE_ORACLE_IMPLEMENTATION(), input.gasPriceOracleImplementation);
        assertEq(xForkContractsManager.L2_STANDARD_BRIDGE_IMPLEMENTATION(), input.l2StandardBridgeImplementation);
        assertEq(xForkContractsManager.SEQUENCER_FEE_WALLET_IMPLEMENTATION(), input.sequencerFeeWalletImplementation);
        assertEq(
            xForkContractsManager.OPTIMISM_MINTABLE_ERC20_FACTORY_IMPLEMENTATION(),
            input.optimismMintableERC20FactoryImplementation
        );
        assertEq(xForkContractsManager.L1_BLOCK_NUMBER_IMPLEMENTATION(), input.l1BlockNumberImplementation);
        assertEq(xForkContractsManager.L2_ERC721_BRIDGE_IMPLEMENTATION(), input.l2ERC721BridgeImplementation);
        assertEq(xForkContractsManager.L1_BLOCK_ATTRIBUTES_IMPLEMENTATION(), input.l1BlockAttributesImplementation);
        assertEq(
            xForkContractsManager.L2_TO_L1_MESSAGE_PASSER_IMPLEMENTATION(), input.l2ToL1MessagePasserImplementation
        );
        assertEq(
            xForkContractsManager.OPTIMISM_MINTABLE_ERC721_FACTORY_IMPLEMENTATION(),
            input.optimismMintableERC721FactoryImplementation
        );
        assertEq(xForkContractsManager.BASE_FEE_VAULT_IMPLEMENTATION(), input.baseFeeVaultImplementation);
        assertEq(xForkContractsManager.L1_FEE_VAULT_IMPLEMENTATION(), input.l1FeeVaultImplementation);
        assertEq(xForkContractsManager.OPERATOR_FEE_VAULT_IMPLEMENTATION(), input.operatorFeeVaultImplementation);
        assertEq(xForkContractsManager.SCHEMA_REGISTRY_IMPLEMENTATION(), input.schemaRegistryImplementation);
        assertEq(xForkContractsManager.EAS_IMPLEMENTATION(), input.easImplementation);
    }
}

/// @title XForkContractsManager_TestUpgrade
/// @notice Tests the upgrade function of the `XForkContractsManager` contract.
contract XForkContractsManager_TestUpgrade is XForkContractsManager_TestInit {
    /// @notice Tests that the upgrade function successfully upgrades all proxies.
    function test_upgrade_succeeds() public {
        XForkContractsManager.Input memory input = _getInput();

        // For each implementation, we expect the proxy to be upgraded to the new implementation.
        _expectUpgradeTo(Predeploys.LEGACY_MESSAGE_PASSER, input.legacyMessagePasserImplementation);
        _expectUpgradeTo(Predeploys.DEPLOYER_WHITELIST, input.deployerWhitelistImplementation);
        _expectUpgradeTo(Predeploys.L2_CROSS_DOMAIN_MESSENGER, input.l2CrossDomainMessengerImplementation);
        _expectUpgradeTo(Predeploys.GAS_PRICE_ORACLE, input.gasPriceOracleImplementation);
        _expectUpgradeTo(Predeploys.L2_STANDARD_BRIDGE, input.l2StandardBridgeImplementation);
        _expectUpgradeTo(Predeploys.SEQUENCER_FEE_WALLET, input.sequencerFeeWalletImplementation);
        _expectUpgradeTo(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY, input.optimismMintableERC20FactoryImplementation);
        _expectUpgradeTo(Predeploys.L1_BLOCK_NUMBER, input.l1BlockNumberImplementation);
        _expectUpgradeTo(Predeploys.L2_ERC721_BRIDGE, input.l2ERC721BridgeImplementation);
        _expectUpgradeTo(Predeploys.L1_BLOCK_ATTRIBUTES, input.l1BlockAttributesImplementation);
        _expectUpgradeTo(Predeploys.L2_TO_L1_MESSAGE_PASSER, input.l2ToL1MessagePasserImplementation);
        _expectUpgradeTo(Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY, input.optimismMintableERC721FactoryImplementation);
        _expectUpgradeTo(Predeploys.BASE_FEE_VAULT, input.baseFeeVaultImplementation);
        _expectUpgradeTo(Predeploys.L1_FEE_VAULT, input.l1FeeVaultImplementation);
        _expectUpgradeTo(Predeploys.OPERATOR_FEE_VAULT, input.operatorFeeVaultImplementation);
        _expectUpgradeTo(Predeploys.SCHEMA_REGISTRY, input.schemaRegistryImplementation);
        _expectUpgradeTo(Predeploys.EAS, input.easImplementation);

        // Perform the actual upgrade.
        xForkContractsManager.upgrade();
    }

    /// @notice Internal helper to expect an upgrade to a specific implementation.
    /// @param proxy The proxy address to expect the upgrade to.
    /// @param implementation The implementation address to expect the upgrade to.
    function _expectUpgradeTo(address proxy, address implementation) internal {
        vm.mockCall(proxy, abi.encodeCall(IProxy.upgradeTo, (implementation)), abi.encode(bytes("")));
        vm.expectCall(proxy, abi.encodeCall(IProxy.upgradeTo, (implementation)));
    }
}
