// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { HandlersParent } from "../handlers/HandlersParent.t.sol";
import { ProposalValidator } from "src/governance/ProposalValidator.sol";

contract PropertiesA is HandlersParent {
    function invariant_sanity() public {
        assert(address(validator.GOVERNOR()) == address(governor));
        assert(address(validator.proposalTypesConfigurator()) == address(proposalTypesConfigurator));
        assert(validator.proposalDistributionThreshold() == DISTRIBUTION_THRESHOLD);
        assert(validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID() == APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID);
        assert(validator.TOP_DELEGATES_ATTESTATION_SCHEMA_UID() == TOP_DELEGATES_ATTESTATION_SCHEMA_UID);
    }

    function invariant_sum_amounts() public {
        uint256 sum = 0;
        for (uint256 i = 0; i < submittedProposals.length; i++) {
            for (uint256 j = 0; j < proposalOptionAmounts[submittedProposals[i]].length; j++) {
                sum += proposalOptionAmounts[submittedProposals[i]][j];
            }
        }
        assert(sum <= DISTRIBUTION_THRESHOLD);
    }

    /// @notice VAL-001: sum of all funding proposals amount moved to vote during a cycle <= that cycle distribution
    /// limit
    function invariant_funding_cycle_limits() public {
        // Check that for each cycle, the total funding moved to vote doesn't exceed the distribution limit
        for (uint256 i = 0; i < 10; i++) {
            assert(ghost_fundingAmountMovedToVotePerCycle[i] <= DISTRIBUTION_LIMIT);
        }
    }

    /// @notice VAL-002: approvalCount == number of delegates having approved it
    function invariant_approval_count() public {
        for (uint256 i = 0; i < submittedProposals.length; i++) {
            bytes32 proposalHash = submittedProposals[i];

            // Get actual proposal data from validator
            (address proposer,,, uint256 actualApprovalCount,) = validator.getProposalData(proposalHash);

            // Skip if proposal doesn't exist (proposer would be zero address)
            if (proposer == address(0)) continue;

            // Get tracked approval count from ghost variables
            uint256 trackedApprovalCount = ghost_proposalApprovalCount[proposalHash];

            // The actual approval count should match what we've tracked
            assert(actualApprovalCount == trackedApprovalCount);
        }
    }

    /// @notice VAL-003: proposal's proposer and type are immutable once submitted (ie hash generated == immutable)
    function invariant_proposer_and_type_immutable() public {
        for (uint256 i = 0; i < submittedProposals.length; i++) {
            bytes32 proposalHash = submittedProposals[i];

            // Get actual proposal data from validator
            (address actualProposer, ProposalValidator.ProposalType actualType,,,) =
                validator.getProposalData(proposalHash);

            // Skip if proposal doesn't exist
            if (actualProposer == address(0)) continue;

            // Get original data recorded at submission time
            address originalProposer = ghost_originalProposer[proposalHash];
            ProposalValidator.ProposalType originalType = ghost_originalProposalType[proposalHash];

            // The actual proposer and type should match what we recorded at submission (immutable)
            if (originalProposer != address(0)) {
                assert(actualProposer == originalProposer);
                assert(actualType == originalType);
            }
        }
    }

    /// @notice VAL-004: proposals go to vote only if approval (+ time window for funding proposals and council member
    /// elections) + "additional" checks have passed
    function invariant_proposals_go_to_vote() public {
        for (uint256 i = 0; i < submittedProposals.length; i++) {
            bytes32 proposalHash = submittedProposals[i];

            // Get actual proposal data from validator
            (address proposer, ProposalValidator.ProposalType proposalType, bool movedToVote, uint256 approvalCount,) =
                validator.getProposalData(proposalHash);

            // Skip if proposal doesn't exist
            if (proposer == address(0)) continue;

            // If a proposal has moved to vote, check the validation conditions
            if (movedToVote) {
                // Check different rules based on proposal type
                if (proposalType == ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade) {
                    // Must have required approvals
                    assert(approvalCount >= PROPOSAL_REQUIRED_APPROVALS);
                } else if (proposalType == ProposalValidator.ProposalType.MaintenanceUpgrade) {
                    // MaintenanceUpgrade moves to vote immediately (no approval needed)
                    // Always valid if it exists
                } else if (
                    proposalType == ProposalValidator.ProposalType.CouncilMemberElections
                        || proposalType == ProposalValidator.ProposalType.GovernanceFund
                        || proposalType == ProposalValidator.ProposalType.CouncilBudget
                ) {
                    // Must have required approvals
                    assert(approvalCount >= PROPOSAL_REQUIRED_APPROVALS);

                    // For funding proposals, also check the cycle limits
                    if (
                        proposalType == ProposalValidator.ProposalType.GovernanceFund
                            || proposalType == ProposalValidator.ProposalType.CouncilBudget
                    ) {
                        uint256 cycle = ghost_proposalVotingCycle[proposalHash];
                        assert(ghost_fundingAmountMovedToVotePerCycle[cycle] <= DISTRIBUTION_LIMIT);
                    }
                }
            }
        }
    }
}
