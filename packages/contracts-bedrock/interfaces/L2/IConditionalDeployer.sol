// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title IConditionalDeployer
/// @notice Interface for the ConditionalDeployer contract.
interface IConditionalDeployer is ISemver {
    /// @notice Emitted when an implementation is deployed.
    /// @param implementation The address of the deployed implementation.
    /// @param salt The salt used for deployment.
    event ImplementationDeployed(address indexed implementation, bytes32 salt);

    /// @notice Emitted when deployment is skipped because implementation already exists.
    /// @param implementation The address of the existing implementation.
    event ImplementationExists(address indexed implementation);

    /// @notice Error thrown when caller is not authorized.
    error ConditionalDeployer_UnauthorizedCaller();

    /// @notice Address of the DeterministicDeploymentProxy (Nick's method).
    function DETERMINISTIC_DEPLOYMENT_PROXY() external view returns (address payable);

    /// @notice Deploys an implementation using CREATE2 if it doesn't already exist.
    /// @dev Only the depositor account or address(0) can call this method.
    /// @param value The amount of ETH to send with the deployment.
    /// @param salt The salt to use for CREATE2 deployment.
    /// @param code The initialization code for the contract.
    /// @return implementation The address of the deployed or existing implementation.
    function deploy(uint256 value, bytes32 salt, bytes memory code) external returns (address implementation);
}
