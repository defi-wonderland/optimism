// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IBundleRelayer
/// @notice An interface for a contract that can be used to relay bundles of messages.
interface IBundleRelayer is IERC165 {
    /// @notice Callback function that is called by the L2ToL2CrossDomainMessenger.
    /// @param _bundle The bundle of messages to relay.
    function onRelayBundle(bytes calldata _bundle) external;
}