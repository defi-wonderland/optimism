// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IStandardCGTBridge } from "interfaces/universal/IStandardCGTBridge.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

/// @title IL2CGTStandardBridge
/// @notice Interface for the L2 Custom Gas Token Standard Bridge
interface IL2CGTStandardBridge is IStandardCGTBridge, ISemver {
    error InsufficientValue();

    function VERSION() external view returns (string memory);
    function initialize(address _cgtToken, ICrossDomainMessenger _messenger, address _otherBridge) external;
    function bridgeCGT(uint32 _minGasLimit, bytes calldata _extraData) external payable;
    function bridgeCGTTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable;
}
