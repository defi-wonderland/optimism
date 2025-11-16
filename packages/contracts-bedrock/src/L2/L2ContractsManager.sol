// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IL1ChugSplashProxy } from "interfaces/legacy/IL1ChugSplashProxy.sol";
import { IAddressManager } from "interfaces/legacy/IAddressManager.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @notice Base contract for L2 Contracts Manager, responsible for orchestrating the upgrades
///         of the L2 contracts during hardforks.
abstract contract L2ContractsManager {
    /// @notice Struct representing the full configuration for an upgrade.
    ///         Relies on specific L2ContractsManager contracts interpretation of the network config required.
    /// @param networkConfig The network specific configuration.
    struct FullConfig {
        bytes networkConfig;
    }

    /// @notice Executes the NUT with after hooks.
    function upgrade() external {
        FullConfig memory _networkConfig = _gatherNetworkConfig();
        _upgrade(_networkConfig);
        _afterUpgrade();
    }

    /// @notice Gather the network specific configuration.
    function _gatherNetworkConfig() internal virtual returns (FullConfig memory);

    /// @notice Hook called after execution.
    function _afterUpgrade() internal virtual;

    /// @notice Performs the proxy upgrades logic.
    function _upgrade(FullConfig memory _networkConfig) internal virtual { }
}
