// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILiquidityMigrator
/// @notice Interface for the LiquidityMigrator contract
interface ILiquidityMigrator {
    event ETHMigrated(uint256 amount);

    function SHARED_LOCKBOX() external view returns (address);

    function migrateETH() external;

    function __constructor__(address _sharedLockbox) external;
}
