// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title IL2CGTFactory
/// @notice Interface for the L2CGTFactory contract, responsible for deploying L2CGTBridge
///         on L2 when triggered by the L1CGTFactory.
interface IL2CGTFactory {
    /// @notice Thrown when the caller is not the expected L1 bridge.
    error IL2CGTFactory_OnlyValidSender();

    /// @notice Emitted when the L2CGTBridge is deployed.
    /// @param l2Bridge Address of the deployed L2CGTBridge.
    /// @param l1Bridge Address of the corresponding L1CGTBridge.
    event L2BridgeDeployed(address indexed l2Bridge, address indexed l1Bridge);

    /// @notice Returns the address of the corresponding L1 bridge.
    /// @return The L1CGTBridge address.
    function l1CGTBridge() external view returns (address);

    /// @notice Returns the address of the L2 bridge owner.
    /// @return The owner address.
    function l2BridgeOwner() external view returns (address);

    /// @notice Returns the address of the LiquidityController.
    /// @return The LiquidityController contract.
    function liquidityController() external view returns (ILiquidityController);

    /// @notice Returns the L2 cross-domain messenger address (predeploy).
    /// @return The L2 messenger contract.
    function L2_MESSENGER() external view returns (ICrossDomainMessenger);

    /// @notice Deploys the L2CGTBridge contract.
    /// @dev This function is called by the L1CGTFactory through cross-domain messaging.
    ///      The L2 messenger is hardcoded as a constant.
    /// @return The address of the deployed L2CGTBridge.
    function deployL2Bridge() external returns (address);
}
