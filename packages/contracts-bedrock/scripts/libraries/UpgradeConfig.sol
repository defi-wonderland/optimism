// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title UpgradeConfig
/// @notice Configuration library for L2 hardfork upgrade transaction generation.
/// @dev Provides gas limits and transaction counts for upgrade bundle generation.
library UpgradeConfig {
    /// @notice The number of implementations always deployed in every upgrade.
    ///         Includes:
    ///         - 21 base predeploys
    ///         - 1 StorageSetter (deployed separately)
    ///         - 2 INTEROP predeploys (CrossL2Inbox, L2ToL2CrossDomainMessenger)
    ///         - 2 CGT predeploys (NativeAssetLiquidity, LiquidityController)
    ///         Total: 26 implementations
    uint256 internal constant IMPLEMENTATION_COUNT = 26;

    /// @notice Gas limits for different types of upgrade transactions.
    /// @param conditionalDeployerDeployment Gas for deploying ConditionalDeployer
    /// @param conditionalDeployerUpgrade Gas for upgrading ConditionalDeployer proxy
    /// @param proxyAdminUpgrade Gas for upgrading ProxyAdmin implementation
    /// @param l2cmDeployment Gas for deploying L2ContractsManager
    /// @param upgradeExecution Gas for L2ProxyAdmin.upgradePredeploys() call
    struct GasLimits {
        // Fixed
        uint64 storageSetterDeployment;
        uint64 l2cmDeployment;
        uint64 upgradeExecution;
        // Jovian
        uint64 conditionalDeployerDeployment;
        uint64 conditionalDeployerUpgrade;
        uint64 proxyAdminUpgrade;
    }

    /// @notice Returns the total number of transactions.
    /// @dev Total count:
    ///      - 26 implementation deployments
    ///      - 2 ConditionalDeployer (deployment + upgrade)
    ///      - 1 ProxyAdmin upgrade
    ///      - 1 L2CM deployment
    ///      - 1 Upgrade Predeploys call
    ///      Total: 31 transactions
    function getTransactionCount() internal pure returns (uint256 txnCount_) {
        txnCount_ = IMPLEMENTATION_COUNT + 5;
    }

    /// @notice Returns the gas limits for all upgrade transaction types.
    /// @dev Gas limits are chosen to provide sufficient headroom while being
    ///      conservative enough to fit within the upgrade block gas allocation.
    ///      Rationale for each limit:
    ///      - TODO: Add rationale here
    /// @return Gas limits struct.
    function gasLimits() internal pure returns (GasLimits memory) {
        return GasLimits({
            // Fixed
            storageSetterDeployment: 375_000,
            l2cmDeployment: 375_000,
            upgradeExecution: type(uint64).max,
            // Jovian
            conditionalDeployerDeployment: 375_000,
            conditionalDeployerUpgrade: 50_000,
            proxyAdminUpgrade: 50_000
        });
    }
}
