// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x420000000000000000000000000000000000002B
/// @title MintingAuth
/// @notice The MintingAuth contract is responsible for locking and unlocking the minting and burning of the native
///         asset on the L2 chain.
contract MintingAuth is ISemver {
    /// @notice Error for when an address is unauthorized to perform un/locking operations
    error MintingAuth_Unauthorized();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Unlocks the minting and burning of the native asset.
    /// @dev Sets transient storage slot 0 to 1.
    function unlock() external {
        if (msg.sender != Predeploys.LIQUIDITY_CONTROLLER) revert MintingAuth_Unauthorized();
        assembly {
            tstore(0, 1)
        }
    }

    /// @notice Locks the minting and burning of the native asset.
    /// @dev Sets transient storage slot 0 to 0.
    function lock() external {
        if (msg.sender != Predeploys.LIQUIDITY_CONTROLLER) revert MintingAuth_Unauthorized();
        assembly {
            tstore(0, 0)
        }
    }
}
