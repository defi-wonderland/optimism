// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IStandardCGTBridge } from "interfaces/universal/IStandardCGTBridge.sol";

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge is IStandardCGTBridge {
    /// @notice Total amount of CGT tokens deposited.
    function cgtDeposits() external view returns (uint256);

    /// @notice Address of the SystemConfig contract.
    function systemConfig() external view returns (ISystemConfig);

    /// @notice Address of the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig);

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external view returns (string memory);
}
