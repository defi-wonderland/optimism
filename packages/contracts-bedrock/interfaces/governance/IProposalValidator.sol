// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGovernanceToken} from "./IGovernanceToken.sol";
import {IOptimismGovernor} from "./IOptimismGovernor.sol";

interface IProposalValidator {
    error ProposalValidator_NotApprovedProposer();
    error ProposalValidator_InvalidProposalType();
    error ProposalValidator_ProposalNotFound();
    error ProposalValidator_InsufficientApprovals();
    error ProposalValidator_AlreadyApproved();
    error ProposalValidator_NotDelegate();
    error ProposalValidator_AlreadyProposed();
    error ProposalValidator_InsufficientVotingPower();
    error ProposalValidator_InvalidAttestation();

    struct ProposalData {
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        ProposalType proposalType;
        bool inVoting;
        mapping(address => bool) delegateApprovals;
        uint256 remainingApprovalsRequired;
    }

    enum ProposalType {
        ProtocolOrGovernorUpgrade,
        MaintenanceUpgradeProposals,
        CouncilMemberElections,
        GovernanceFund,
        CouncilBudget
    }

    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        ProposalType proposalType
    );

    event ProposalApproved(
        uint256 indexed proposalId,
        address indexed approver
    );

    event ProposalMovedToVote(
        uint256 indexed proposalId,
        address indexed executor
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType,
        bytes32 attestationUid
    ) external returns (uint256);

    function approveProposal(uint256 proposalId) external;

    function moveToVote(uint256 proposalId) external returns (uint256);
    
    function setMinimumVotingPower(uint256 _minimumVotingPower) external;
    
    function renounceOwnership() external;
    
    function canSignOff(address _delegate) external view returns (bool);
    
    function setVotingToken(IGovernanceToken _votingToken) external;
    
    function transferOwnership(address newOwner) external;

    function minimumVotingPower() external view returns (uint256);

    function votingToken() external view returns (IGovernanceToken);

    function governor() external view returns (IOptimismGovernor);

    function owner() external view returns (address);

    function ATTESTATION_SCHEMA_UID() external view returns (bytes32);
    
    function __constructor__(address _owner, IOptimismGovernor _governor, IGovernanceToken _votingToken, bytes32 _attestationSchemaUid) external;
}
