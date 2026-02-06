// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Types } from "src/libraries/Types.sol";

/// @title IL2ContractsManager
/// @notice Interface for managing L2 predeploy upgrades. Each L2ContractsManager instance is
///         purpose-built for a specific upgrade and is invoked via DELEGATECALL from L2ProxyAdmin.
///         The contract is stateless - all upgrade logic and addresses are embedded in bytecode.
interface IL2ContractsManager {
    /// @notice Configuration for L2CrossDomainMessenger (0x4200...0007).
    struct CrossDomainMessengerConfig {
        address otherMessenger;
    }

    /// @notice Configuration for L2StandardBridge (0x4200...0010).
    struct StandardBridgeConfig {
        address otherBridge;
    }

    /// @notice Configuration for L2ERC721Bridge (0x4200...0014).
    struct ERC721BridgeConfig {
        address otherBridge;
    }

    /// @notice Configuration for OptimismMintableERC20Factory (0x4200...0012).
    struct MintableERC20FactoryConfig {
        address bridge;
    }

    /// @notice Configuration for a FeeVault contract.
    struct FeeVaultConfig {
        address recipient;
        uint256 minWithdrawalAmount;
        Types.WithdrawalNetwork withdrawalNetwork;
    }

    /// @notice Configuration for LiquidityController (0x4200...002A).
    struct LiquidityControllerConfig {
        address owner;
        string gasPayingTokenName;
        string gasPayingTokenSymbol;
    }

    /// @notice Configuration for FeeSplitter (0x4200...002B).
    struct FeeSplitterConfig {
        address sharesCalculator;
    }

    // -------- Main Config Struct --------

    /// @notice Full network-specific configuration gathered from existing predeploys.
    ///         These values are read before upgrade and passed to initializers after.
    struct FullConfig {
        CrossDomainMessengerConfig crossDomainMessenger;
        StandardBridgeConfig standardBridge;
        ERC721BridgeConfig erc721Bridge;
        MintableERC20FactoryConfig mintableERC20Factory;
        FeeVaultConfig sequencerFeeVault;
        FeeVaultConfig baseFeeVault;
        FeeVaultConfig l1FeeVault;
        FeeVaultConfig operatorFeeVault;
        LiquidityControllerConfig liquidityController;
        FeeSplitterConfig feeSplitter;
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
