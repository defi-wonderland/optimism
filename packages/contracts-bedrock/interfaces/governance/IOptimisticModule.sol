// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @title IOptimisticModule
/// @notice Interface for the Optimistic Module containing only the essential types
///         needed by the ProposalValidator contract.
interface IOptimisticModule {
    struct ProposalSettings {
        uint248 againstThreshold;
        bool isRelativeToVotableSupply;
    }
}