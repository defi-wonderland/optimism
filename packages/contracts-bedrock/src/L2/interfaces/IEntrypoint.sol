// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IEntrypoint
/// @notice Interface for contracts serving as entry points for the relaying process via L2ToL2CrossDomainMessenger.
interface IEntrypoint {
    /// @notice Executes logic in the entrypoint contract before relaying the message.
    ///         This method is called by the L2ToL2CrossDomainMessenger before relaying the message and passing the
    ///         context that was used in the origin chain.
    /// @param _context The context data for the relay message, passed as bytes.
    /// @return success_ A boolean indicating whether the operation was successful.
    function onRelayMessage(bytes calldata _context) external returns (bool success_);
}
