// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICrossMessageBundler
/// @notice An interface for a contract that can be used to create cross-domain message bundles.
interface ICrossMessageBundler {
    /// @notice Callback function that is called by the L2ToL2CrossDomainMessenger when a bundle is created.
    /// @param _context The context of the bundle.
    function onCreateBundle(bytes calldata _context) external;
}
