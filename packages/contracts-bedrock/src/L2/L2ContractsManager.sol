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
            ProxyUpgrade memory proxyUpgrade = proxyUpgrades[i];

            // Access ProxyAdmin's proxyType storage via public getter (we're in its context)
            IProxyAdmin.ProxyType ptype = IProxyAdmin(address(this)).proxyType(proxyUpgrade.proxy);

            if (ptype == IProxyAdmin.ProxyType.ERC1967) {
                IProxy(payable(proxyUpgrade.proxy)).upgradeTo(proxyUpgrade.implementation);
            } else if (ptype == IProxyAdmin.ProxyType.CHUGSPLASH) {
                IL1ChugSplashProxy(payable(proxyUpgrade.proxy)).setStorage(
                    Constants.PROXY_IMPLEMENTATION_ADDRESS, bytes32(uint256(uint160(proxyUpgrade.implementation)))
                );
            } else if (ptype == IProxyAdmin.ProxyType.RESOLVED) {
                string memory name = IProxyAdmin(address(this)).implementationName(proxyUpgrade.proxy);
                IAddressManager(IProxyAdmin(address(this)).addressManager()).setAddress(
                    name, proxyUpgrade.implementation
                );
            } else {
                // Should not be possible, but matches ProxyAdmin's assert(false)
                revert("XForkContractsManager: unknown proxy type");
            }
        }

        return abi.encode(true);
    }
}
