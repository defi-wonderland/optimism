// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title IL2ProxyAdmin
contract IL2ProxyAdmin is IProxyAdmin {
    /// @notice Thrown when the caller is not the owner or the depositor account.
    error IL2ProxyAdmin__InvalidCaller();

    /// @notice Thrown when the upgrade fails.
    error IL2ProxyAdmin__UpgradeFailed(bytes data);

    /// @notice Upgrades the predeploys via delegatecall to the xForkL2ContractsManager contract.
    /// @param xForkL2ContractsManager Address of the xForkL2ContractsManager contract.
    function upgradePredeploys(address xForkL2ContractsManager) external;
}
