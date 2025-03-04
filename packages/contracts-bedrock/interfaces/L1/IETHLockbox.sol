// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IProxyAdminOwnerBase } from "interfaces/L1/IProxyAdminOwnerBase.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

interface IETHLockbox is IProxyAdminOwnerBase, ISemver {
    error ETHLockbox_Unauthorized();
    error ETHLockbox_Paused();
    error ETHLockbox_InsufficientBalance();
    error ETHLockbox_NoWithdrawalTransactions();
    error ETHLockbox_DifferentProxyAdminOwner();

    event Initialized(uint8 version);
    event ETHLocked(address indexed portal, uint256 amount);
    event ETHUnlocked(address indexed portal, uint256 amount);
    event PortalAuthorized(address indexed portal);
    event LockboxAuthorized(address indexed lockbox);
    event LiquidityMigrated(address indexed lockbox);
    event LiquidityReceived(address indexed lockbox);

    function initialize(ISuperchainConfig _superchainConfig, IOptimismPortal2[] calldata _portals) external;
    function superchainConfig() external view returns (ISuperchainConfig);
    function paused() external view returns (bool);
    function authorizedPortals(address) external view returns (bool);
    function authorizedLockboxes(address) external view returns (bool);
    function receiveLiquidity() external payable;
    function lockETH() external payable;
    function unlockETH(uint256 _value) external;
    function authorizePortal(IOptimismPortal2 _portal) external;
    function authorizeLockbox(IETHLockbox _lockbox) external;
    function migrateLiquidity(IETHLockbox _lockbox) external;

    function __constructor__() external;
}
