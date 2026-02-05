// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Constants } from "src/libraries/Constants.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x420000000000000000000000000000000000002C
/// @title ConditionalDeployer
/// @notice ConditionalDeployer is used to deploy implementations for predeploys during network upgrades.
///         It uses the DeterministicDeploymentProxy (Nick's method) to deploy the implementations.
contract ConditionalDeployer is ISemver {
    /// @notice Address of the DeterministicDeploymentProxy (Nick's method).
    address payable public constant DETERMINISTIC_DEPLOYMENT_PROXY = payable(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    /// @notice Emitted when an implementation is deployed.
    /// @param implementation The address of the deployed implementation.
    /// @param salt The salt used for deployment.
    event ImplementationDeployed(address indexed implementation, bytes32 salt);

    /// @notice Emitted when deployment is skipped because implementation already exists.
    /// @param implementation The address of the existing implementation.
    event ImplementationExists(address indexed implementation);

    /// @notice Error thrown when caller is not authorized.
    error ConditionalDeployer_UnauthorizedCaller();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Deploys an implementation using CREATE2 if it doesn't already exist.
    /// @dev Only the depositor account or address(0) can call this method.
    /// @param value The amount of ETH to send with the deployment.
    /// @param salt The salt to use for CREATE2 deployment.
    /// @param code The initialization code for the contract.
    /// @return implementation The address of the deployed or existing implementation.
    function deploy(uint256 value, bytes32 salt, bytes memory code) external returns (address implementation) {
        // Restrict access to depositor account or address(0).
        if (msg.sender != Constants.DEPOSITOR_ACCOUNT && msg.sender != address(0)) {
            revert ConditionalDeployer_UnauthorizedCaller();
        }

        // Compute the address where the contract will be deployed using CREATE2 formula
        bytes32 codeHash = keccak256(code);
        implementation = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), DETERMINISTIC_DEPLOYMENT_PROXY, salt, codeHash))))
        );

        // Check if implementation already exists
        if (implementation.code.length != 0) {
            emit ImplementationExists(implementation);
            return implementation;
        }

        // Deploy using DeterministicDeploymentProxy (Nick's method)
        // Calldata format: salt + initcode
        (bool success,) = DETERMINISTIC_DEPLOYMENT_PROXY.call{ value: value }(abi.encodePacked(salt, code));
        require(success, "ConditionalDeployer: deployment failed");

        emit ImplementationDeployed(implementation, salt);
        return implementation;
    }
}
