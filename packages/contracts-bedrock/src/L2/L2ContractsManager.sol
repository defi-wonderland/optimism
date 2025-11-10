// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IL1ChugSplashProxy } from "interfaces/legacy/IL1ChugSplashProxy.sol";
import { IAddressManager } from "interfaces/legacy/IAddressManager.sol";
import { Constants } from "src/libraries/Constants.sol";

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
        bytes memory returnData = _performUpgrades(proxyUpgrades);
        _afterExecution(returnData);
        return returnData;
    }

    /// @notice Hook called before execution.
    function _beforeExecution() internal virtual;

    /// @notice Hook called after execution.
    /// @param returnData Data returned from execution.
    function _afterExecution(bytes memory returnData) internal virtual;

    /// @notice Performs the proxy upgrades logic.
    /// @param proxyUpgrades Data for the proxy upgrades.
    /// @return returnData Return data from the execution.
    function _performUpgrades(ProxyUpgrade[] memory proxyUpgrades) internal virtual returns (bytes memory returnData) {
        for (uint256 i = 0; i < proxyUpgrades.length; i++) {
            IProxy(payable(proxyUpgrades[i].proxy)).upgradeTo(proxyUpgrades[i].implementation);
        }

        return abi.encode(true);
    }
}
