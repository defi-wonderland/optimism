// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IStandardCGTBridge } from "interfaces/universal/IStandardCGTBridge.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge is IStandardCGTBridge, ISemver {
    /// @notice Address of the SystemConfig contract.
    function systemConfig() external view returns (ISystemConfig);

    /// @notice Address of the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig);

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function VERSION() external view returns (string memory);

    function bridgeCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external virtual;

    function bridgeCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        virtual;
}
