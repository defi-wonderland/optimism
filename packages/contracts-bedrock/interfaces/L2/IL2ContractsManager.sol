// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2ContractsManager
/// @notice Interface for managing L2 predeploy upgrades.
interface IL2ContractsManager {
    /// @notice Full configuration for an L2 predeploy upgrade.
    ///         Contains all the network configuration stored in the system predeploys.
    struct FullConfig {
        address a;
    }

    /// @notice All the implementations for each of the non-deprecated predeploys in OP Stack Chains.
    struct UpgradeImplementations {
        address storageSetterImpl;
        address wethImpl;
        address l2CrossDomainMessengerImpl;
        address gasPriceOracleImpl;
        address l2StandardBridgeImpl;
        address sequencerFeeWalletImpl;
        address optimismMintableERC20FactoryImpl;
        address l2ERC721BridgeImpl;
        address l1BlockAttributesImpl;
        address l2ToL1MessagePasserImpl;
        address optimismMintableERC721FactoryImpl;
        address proxyAdminImpl;
        address baseFeeVaultImpl;
        address l1FeeVaultImpl;
        address operatorFeeVaultImpl;
        address schemaRegistryImpl;
        address easImpl;
        address governanceTokenImpl;
        address crossL2InboxImpl;
        address l2ToL2CrossDomainMessengerImpl;
        address superchainETHBridgeImpl;
        address ethLiquidityImpl;
        address optimismSuperchainERC20FactoryImpl;
        address optimismSuperchainERC20BeaconImpl;
        address superchainTokenBridgeImpl;
        address nativeAssetLiquidityImpl;
        address liquidityControllerImpl;
        address feeSplitterImpl;
    }

    /// @notice Thrown when the upgrade is not called via DELEGATECALL from L2ProxyAdmin.
    error OnlyDelegatecall();

    /// @notice Thrown when an upgrade operation fails.
    error UpgradeFailed();

    /// @notice Returns the semantic version of this contract.
    function version() external pure returns (string memory);

    /// @notice Executes the upgrade for all predeploys managed by this L2ContractsManager.
    ///         MUST be called via DELEGATECALL from L2ProxyAdmin.
    ///         Gathers configuration from existing predeploys, then for each predeploy:
    ///         1. Upgrades to StorageSetter and resets initialized state
    ///         2. Upgrades to new implementation via upgradeToAndCall with preserved config
    /// @dev All upgrades succeed or fail atomically per iL2CM-003.
    function upgrade() external;
}
