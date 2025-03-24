// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Claim } from "src/dispute/lib/Types.sol";

/// @notice Interface for the OPCM pre-version 1.13.0.
/// @dev This is a temporary interface to allow the OPCM to be upgraded to version 1.13.0.
interface IOPContractsManagerPre113 {
    struct OpChainConfig {
        ISystemConfig systemConfigProxy;
        IProxyAdmin proxyAdmin;
        Claim absolutePrestate;
    }

    function upgrade(OpChainConfig[] memory _opChainConfigs) external;
}
