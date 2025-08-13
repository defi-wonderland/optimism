// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IStandardCGTBridge } from "interfaces/universal/IStandardCGTBridge.sol";

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge {
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    error InvalidAmount();

    error Paused();

    error OnlyOtherBridge();

    function cgtToken() external view returns (address);

    function messenger() external view returns (ICrossDomainMessenger);

    function otherBridge() external view returns (IStandardCGTBridge);

    function superchainConfig() external view returns (ISuperchainConfig);

    function optimismPortal() external view returns (IOptimismPortal2);

    function cgtDeposits() external view returns (uint256);

    function VERSION() external view returns (string memory);

    function paused() external view returns (bool);

    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external;

    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;
}
