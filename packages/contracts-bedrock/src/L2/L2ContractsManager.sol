// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @notice Base contract for L2 Contracts Manager, responsible for orquestrating the upgrades
///         of the L2 contracts during hardforks.
abstract contract L2ContractsManager {
    /// @notice Struct representing the data for an upgrade.
    struct ProxyUpgrade {
        address proxy;
        address implementation;
    }

    /// @notice Executes the NUT with before/after hooks.
    /// @param proxyUpgrades Data for the proxy upgrades.
    /// @return Return data from the execution.
    function execute(ProxyUpgrade[] memory proxyUpgrades) external returns (bytes memory) {
        _beforeExecution();
        bytes memory returnData = _performExecute(proxyUpgrades);
        _afterExecution(returnData);
        return returnData;
    }

    /// @notice Hook called before execution.
    function _beforeExecution() internal virtual;

    /// @notice Hook called after execution.
    /// @param returnData Data returned from execution.
    function _afterExecution(bytes memory returnData) internal virtual;

    /// @notice Performs the actual execution logic.
    /// @param proxyUpgrades Data for the proxy upgrades.
    /// @return returnData Return data from the execution.
    function _performExecute(ProxyUpgrade[] memory proxyUpgrades) internal virtual returns (bytes memory returnData);
}
