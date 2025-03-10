// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";

interface IL1CrossDomainMessenger is ICrossDomainMessenger {
    event Initialized(uint8 version);

    function PORTAL() external view returns (IOptimismPortal portal_);
    function initialize(ISuperchainConfig _superchainConfig, IOptimismPortal _portal) external;
    function portal() external view returns (IOptimismPortal portal_);
    function superchainConfig() external view returns (ISuperchainConfig superchainConfig_);
    function version() external view returns (string memory version_);

    function __constructor__() external;
}
