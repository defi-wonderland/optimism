// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title IL1CGTFactory
/// @notice Interface for the L1CGTFactory contract, responsible for deploying L1CGTBridge
///         and triggering the deployment of L2CGTBridge with precalculated addresses.
interface IL1CGTFactory {
    /// @notice Struct containing L2 deployment parameters.
    struct L2Deployments {
        /// @notice Address of the L2 bridge owner.
        address l2BridgeOwner;
        /// @notice Address of the L2 LiquidityController contract.
        address liquidityController;
        /// @notice Minimum gas limit for the L2 factory deployment.
        uint32 minGasLimitDeploy;
        /// @notice Minimum gas limit for the L2 bridge deployment.
        uint32 minGasLimitBridge;
    }

    /// @notice Emitted when a new CGT bridge protocol is deployed.
    /// @param l1Bridge Address of the deployed L1CGTBridge.
    /// @param l2Factory Address of the deployed L2CGTFactory.
    /// @param l2Bridge Address of the precalculated L2CGTBridge.
    event ProtocolDeployed(address indexed l1Bridge, address indexed l2Factory, address indexed l2Bridge);

    /// @notice Returns the L2 CREATE2 deployer address.
    /// @return The address of the L2 CREATE2 deployer.
    function L2_CREATE2_DEPLOYER() external view returns (address);

    /// @notice Returns the CGT token address.
    /// @return The CGT token contract.
    function cgtToken() external view returns (IERC20);

    /// @notice Returns the current deployments salt counter.
    /// @return The current salt counter value.
    function deploymentsSaltCounter() external view returns (uint256);

    /// @notice Deploys the L1 bridge and triggers L2 deployments.
    /// @param _l1Messenger The address of the L1 messenger for the L2 Op chain.
    /// @param _superchainConfig The address of the SuperchainConfig contract.
    /// @param _systemConfig The address of the SystemConfig contract.
    /// @param _l1BridgeOwner The address of the owner of the L1 bridge.
    /// @param _chainName The name of the L2 Op chain.
    /// @param _l2Deployments The deployments data for the L2 factory and bridge.
    /// @return _l1Bridge The address of the L1 bridge.
    /// @return _l2Factory The address of the L2 factory.
    /// @return _l2Bridge The address of the L2 bridge.
    function deploy(
        ICrossDomainMessenger _l1Messenger,
        ISuperchainConfig _superchainConfig,
        ISystemConfig _systemConfig,
        address _l1BridgeOwner,
        string calldata _chainName,
        L2Deployments calldata _l2Deployments
    )
        external
        returns (address _l1Bridge, address _l2Factory, address _l2Bridge);
}
