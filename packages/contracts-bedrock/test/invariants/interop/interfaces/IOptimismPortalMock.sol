// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Types } from "src/libraries/Types.sol";

/// @dev Interface defined with modified functions interfaces on the OptimismPortalMock contract for
///      testing purposes only.
interface IOptimismPortalMock {
    /// @notice Proves a withdrawal transaction using an Output Root proof. Only callable when the
    ///         OptimismPortal is using Output Roots (superRootsActive flag is false).
    /// @dev    Added this function to prevent functions with the same name from being used in the
    ///         same interface.
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

    /// @notice Finalizes a withdrawal transaction.
    /// @dev Added a return of the success of the call to the target contract.
    /// @param _tx Withdrawal transaction to finalize.
    /// @return success_ True if the withdrawal transaction was successfully finalized, false otherwise.
    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external returns (bool);
}
