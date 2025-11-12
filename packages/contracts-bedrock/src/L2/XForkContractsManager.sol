// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { IProxy } from "interfaces/universal/IProxy.sol";

/// @title XForkContractsManager
/// @notice The XForkContractsManager is responsible for orquestrating the upgrades of the L2 contracts during xFork
/// hardforks.
contract XForkContractsManager is L2ContractsManager {
    error InvalidInput();

    struct Input {
        address legacyMessagePasserImplementation; // 0: LegacyMessagePasser
        address deployerWhitelistImplementation; // 1: DeployerWhitelist
        address l2CrossDomainMessengerImplementation; // 2: L2CrossDomainMessenger
        address gasPriceOracleImplementation; // 3: GasPriceOracle
        address l2StandardBridgeImplementation; // 4: L2StandardBridge
        address sequencerFeeWalletImplementation; // 5: SequencerFeeWallet
        address optimismMintableERC20FactoryImplementation; // 6: OptimismMintableERC20Factory
        address l1BlockNumberImplementation; // 7: L1BlockNumber
        address l2ERC721BridgeImplementation; // 8: L2ERC721Bridge
        address l1BlockAttributesImplementation; // 9: L1Block
        address l2ToL1MessagePasserImplementation; // 10: L2ToL1MessagePasser
        address optimismMintableERC721FactoryImplementation; // 11: OptimismMintableERC721Factory
        address baseFeeVaultImplementation; // 12: BaseFeeVault
        address l1FeeVaultImplementation; // 13: L1FeeVault
        address operatorFeeVaultImplementation; // 14: OperatorFeeVault
        address schemaRegistryImplementation; // 15: SchemaRegistry
        address easImplementation; // 16: EAS
    }

    address internal immutable LEGACY_MESSAGE_PASSER_IMPLEMENTATION;
    address internal immutable DEPLOYER_WHITELIST_IMPLEMENTATION;
    address internal immutable L2_CROSS_DOMAIN_MESSENGER_IMPLEMENTATION;
    address internal immutable GAS_PRICE_ORACLE_IMPLEMENTATION;
    address internal immutable L2_STANDARD_BRIDGE_IMPLEMENTATION;
    address internal immutable SEQUENCER_FEE_WALLET_IMPLEMENTATION;
    address internal immutable OPTIMISM_MINTABLE_ERC20_FACTORY_IMPLEMENTATION;
    address internal immutable L1_BLOCK_NUMBER_IMPLEMENTATION;
    address internal immutable L2_ERC721_BRIDGE_IMPLEMENTATION;
    address internal immutable L1_BLOCK_ATTRIBUTES_IMPLEMENTATION;
    address internal immutable L2_TO_L1_MESSAGE_PASSER_IMPLEMENTATION;
    address internal immutable OPTIMISM_MINTABLE_ERC721_FACTORY_IMPLEMENTATION;
    address internal immutable BASE_FEE_VAULT_IMPLEMENTATION;
    address internal immutable L1_FEE_VAULT_IMPLEMENTATION;
    address internal immutable OPERATOR_FEE_VAULT_IMPLEMENTATION;
    address internal immutable SCHEMA_REGISTRY_IMPLEMENTATION;
    address internal immutable EAS_IMPLEMENTATION;

    constructor(Input memory _input) {
        if (
            _input.legacyMessagePasserImplementation == address(0)
                || _input.deployerWhitelistImplementation == address(0)
                || _input.l2CrossDomainMessengerImplementation == address(0)
                || _input.gasPriceOracleImplementation == address(0) || _input.l2StandardBridgeImplementation == address(0)
                || _input.sequencerFeeWalletImplementation == address(0)
                || _input.optimismMintableERC20FactoryImplementation == address(0)
                || _input.l1BlockNumberImplementation == address(0) || _input.l2ERC721BridgeImplementation == address(0)
                || _input.l1BlockAttributesImplementation == address(0)
                || _input.l2ToL1MessagePasserImplementation == address(0)
                || _input.optimismMintableERC721FactoryImplementation == address(0)
                || _input.baseFeeVaultImplementation == address(0) || _input.l1FeeVaultImplementation == address(0)
                || _input.operatorFeeVaultImplementation == address(0) || _input.schemaRegistryImplementation == address(0)
                || _input.easImplementation == address(0)
        ) {
            revert InvalidInput();
        }
        LEGACY_MESSAGE_PASSER_IMPLEMENTATION = _input.legacyMessagePasserImplementation;
        DEPLOYER_WHITELIST_IMPLEMENTATION = _input.deployerWhitelistImplementation;
        L2_CROSS_DOMAIN_MESSENGER_IMPLEMENTATION = _input.l2CrossDomainMessengerImplementation;
        GAS_PRICE_ORACLE_IMPLEMENTATION = _input.gasPriceOracleImplementation;
        L2_STANDARD_BRIDGE_IMPLEMENTATION = _input.l2StandardBridgeImplementation;
        SEQUENCER_FEE_WALLET_IMPLEMENTATION = _input.sequencerFeeWalletImplementation;
        OPTIMISM_MINTABLE_ERC20_FACTORY_IMPLEMENTATION = _input.optimismMintableERC20FactoryImplementation;
        L1_BLOCK_NUMBER_IMPLEMENTATION = _input.l1BlockNumberImplementation;
        L2_ERC721_BRIDGE_IMPLEMENTATION = _input.l2ERC721BridgeImplementation;
        L1_BLOCK_ATTRIBUTES_IMPLEMENTATION = _input.l1BlockAttributesImplementation;
        L2_TO_L1_MESSAGE_PASSER_IMPLEMENTATION = _input.l2ToL1MessagePasserImplementation;
        OPTIMISM_MINTABLE_ERC721_FACTORY_IMPLEMENTATION = _input.optimismMintableERC721FactoryImplementation;
        BASE_FEE_VAULT_IMPLEMENTATION = _input.baseFeeVaultImplementation;
        L1_FEE_VAULT_IMPLEMENTATION = _input.l1FeeVaultImplementation;
        OPERATOR_FEE_VAULT_IMPLEMENTATION = _input.operatorFeeVaultImplementation;
        SCHEMA_REGISTRY_IMPLEMENTATION = _input.schemaRegistryImplementation;
        EAS_IMPLEMENTATION = _input.easImplementation;
    }

    /// @notice Hook called before execution.
    function _beforeExecution() internal override { }

    /// @notice Hook called after execution.
    function _afterExecution(bytes memory returnData) internal override { }

    function _performUpgrades() internal override returns (bytes memory returnData) {
        IProxy(payable(Predeploys.LEGACY_MESSAGE_PASSER)).upgradeTo(LEGACY_MESSAGE_PASSER_IMPLEMENTATION);
        IProxy(payable(Predeploys.DEPLOYER_WHITELIST)).upgradeTo(DEPLOYER_WHITELIST_IMPLEMENTATION);
        IProxy(payable(Predeploys.L2_CROSS_DOMAIN_MESSENGER)).upgradeTo(L2_CROSS_DOMAIN_MESSENGER_IMPLEMENTATION);
        IProxy(payable(Predeploys.GAS_PRICE_ORACLE)).upgradeTo(GAS_PRICE_ORACLE_IMPLEMENTATION);
        IProxy(payable(Predeploys.L2_STANDARD_BRIDGE)).upgradeTo(L2_STANDARD_BRIDGE_IMPLEMENTATION);
        IProxy(payable(Predeploys.SEQUENCER_FEE_WALLET)).upgradeTo(SEQUENCER_FEE_WALLET_IMPLEMENTATION);
        IProxy(payable(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY)).upgradeTo(
            OPTIMISM_MINTABLE_ERC20_FACTORY_IMPLEMENTATION
        );
        IProxy(payable(Predeploys.L1_BLOCK_NUMBER)).upgradeTo(L1_BLOCK_NUMBER_IMPLEMENTATION);
        IProxy(payable(Predeploys.L2_ERC721_BRIDGE)).upgradeTo(L2_ERC721_BRIDGE_IMPLEMENTATION);
        IProxy(payable(Predeploys.L1_BLOCK_ATTRIBUTES)).upgradeTo(L1_BLOCK_ATTRIBUTES_IMPLEMENTATION);
        IProxy(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).upgradeTo(L2_TO_L1_MESSAGE_PASSER_IMPLEMENTATION);
        IProxy(payable(Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY)).upgradeTo(
            OPTIMISM_MINTABLE_ERC721_FACTORY_IMPLEMENTATION
        );
        IProxy(payable(Predeploys.BASE_FEE_VAULT)).upgradeTo(BASE_FEE_VAULT_IMPLEMENTATION);
        IProxy(payable(Predeploys.L1_FEE_VAULT)).upgradeTo(L1_FEE_VAULT_IMPLEMENTATION);
        IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).upgradeTo(OPERATOR_FEE_VAULT_IMPLEMENTATION);
        IProxy(payable(Predeploys.SCHEMA_REGISTRY)).upgradeTo(SCHEMA_REGISTRY_IMPLEMENTATION);
        IProxy(payable(Predeploys.EAS)).upgradeTo(EAS_IMPLEMENTATION);
        return abi.encode(true);
    }
}
