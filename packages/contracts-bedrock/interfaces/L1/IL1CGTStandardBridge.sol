// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL2CGTStandardBridge } from "interfaces/L2/IL2CGTStandardBridge.sol";
import { IProxyAdminOwnedBase } from "interfaces/L1/IProxyAdminOwnedBase.sol";
import { IReinitializableBase } from "interfaces/universal/IReinitializableBase.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge is IProxyAdminOwnedBase, IReinitializableBase, ISemver {
    event Initialized(uint8 version);

    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    error InvalidAmount();
    error Paused();
    error OnlyOtherBridge();

    function cgtToken() external view returns (address);
    function messenger() external view returns (ICrossDomainMessenger);
    function otherBridge() external view returns (IL2CGTStandardBridge);
    function systemConfig() external view returns (ISystemConfig);
    function superchainConfig() external view returns (ISuperchainConfig);
    function optimismPortal() external view returns (IOptimismPortal2);
    function cgtDeposits() external view returns (uint256);
    function VERSION() external view returns (string memory);
    function paused() external view returns (bool);
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        IL2CGTStandardBridge _otherBridge,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        IOptimismPortal2 _optimismPortal
    )
        external;
    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external;
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;
}
