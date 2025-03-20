// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Types } from "src/libraries/Types.sol";

/// @dev Only used to define just one function for proving a withdrawal transaction instead of 2,
///      to be able to use `abi.encodeCall()`
interface IOptimismPortalSingleProveWithdrawal {
    /// @notice Proves a withdrawal transaction using an Output Root proof. Only callable when the
    ///         OptimismPortal is using Output Roots (superRootsActive flag is false).
    /// @param _tx               Withdrawal transaction to finalize.
    /// @param _disputeGameIndex Index of the dispute game to prove the withdrawal against.
    /// @param _outputRootProof  Inclusion proof of the L2ToL1MessagePasser storage root.
    /// @param _withdrawalProof  Inclusion proof of the withdrawal within the L2ToL1MessagePasser.
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256 _disputeGameIndex,
        Types.OutputRootProof memory _outputRootProof,
        bytes[] memory _withdrawalProof
    )
        external;
}
