// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VotingModule} from "src/governance/VotingModule.sol";
import {IOptimismGovernor} from "./IOptimismGovernor.sol";
import {IGovernanceToken} from "./IGovernanceToken.sol";

interface IDelegatesProposalValidator {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DelegatesProposalValidator_NotApprovedProposer();
    error DelegatesProposalValidator_InvalidProposalType();
    error DelegatesProposalValidator_ProposalNotFound();
    error DelegatesProposalValidator_InsufficientApprovals();
    error DelegatesProposalValidator_AlreadyApproved();
    error DelegatesProposalValidator_NotDelegate();
    error DelegatesProposalValidator_AlreadyProposed();
    error DelegatesProposalValidator_InsufficientVotingPower();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalData {
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint8 proposalType;
        bool inVoting;
        mapping(address => bool) delegateApprovals;
        uint256 remainingApprovalsRequired;
    }

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    function governor() external view returns (IOptimismGovernor);
    function minimumVotingPower() external view returns (uint256);
    function votingToken() external view returns (IGovernanceToken);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        uint8 proposalType
    );

    event ProposalApproved(
        uint256 indexed proposalId,
        address indexed approver
    );

    event ProposalMovedToVote(
        uint256 indexed proposalId,
        address indexed executor
    );

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) external returns (uint256 proposalId);

    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) external returns (uint256 proposalId);

    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) external returns (uint256 proposalId);

    function approveProposal(uint256 proposalId) external;

    function moveToVote(uint256 proposalId) external returns (uint256 governorProposalId);
    
    function setMinimumVotingPower(uint256 minimumVotingPower) external;

    function setProposalDeadline(uint256 proposalId, uint64 deadline) external;
    
    function setVotingDelay(uint256 newVotingDelay) external;
    
    function setVotingPeriod(uint256 newVotingPeriod) external;
    
    function setProposalThreshold(uint256 newProposalThreshold) external;
}
