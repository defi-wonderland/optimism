// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOptimismGovernor} from "./IOptimismGovernor.sol";
import {IGovernanceToken} from "./IGovernanceToken.sol";

interface IProposalValidator {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ProposalValidator_NotApprovedProposer();
    error ProposalValidator_InvalidProposalType();
    error ProposalValidator_ProposalNotFound();
    error ProposalValidator_InsufficientApprovals();
    error ProposalValidator_AlreadyApproved();
    error ProposalValidator_NotDelegate();
    error ProposalValidator_AlreadyProposed();
    error ProposalValidator_InsufficientVotingPower();
    error ProposalValidator_InvalidAttestation();
    error ProposalValidator_InvalidProposalData();
    error ProposalValidator_UnexistentProposal();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalData {
        address proposer;
        ProposalType proposalType;
        uint8 proposalTypeConfigurator;
        bool inVoting;
        mapping(address => bool) delegateApprovals;
        uint256 remainingApprovalsRequired;
    }
    
    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    enum ProposalType {
        ProtocolOrGovernorUpgrade,
        MaintenanceUpgradeProposals,
        CouncilMemberElections,
        GovernanceFund,
        CouncilBudget
    }

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    function governor() external view returns (IOptimismGovernor);
    function minimumVotingPower() external view returns (uint256);
    function votingToken() external view returns (IGovernanceToken);
    function ATTESTATION_SCHEMA_UID() external view returns (bytes32);
    function owner() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalSubmitted(
        bytes32 indexed proposalHash,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        ProposalType proposalType,
        uint8 proposalTypeConfigurator
    );

    event ProposalApproved(
        bytes32 indexed proposalHash,
        address indexed approver
    );

    event ProposalMovedToVote(
        bytes32 indexed proposalHash,
        address indexed executor
    );

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType,
        uint8 proposalTypeConfigurator,
        bytes32 attestationUid
    ) external returns (bytes32 proposalHash_);

    function approveProposal(bytes32 proposalHash) external;

    function moveToVote(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);
    
    function setMinimumVotingPower(uint256 _minimumVotingPower) external;

    function setProposalDeadline(uint256 _proposalId, uint64 _deadline) external;
    
    function setVotingDelay(uint256 _newVotingDelay) external;
    
    function setVotingPeriod(uint256 _newVotingPeriod) external;
    
    function setProposalThreshold(uint256 _newProposalThreshold) external;

    function setVotingToken(IGovernanceToken _votingToken) external;

    function transferOwnership(address newOwner) external;

    function renounceOwnership() external;

    function canSignOff(address _delegate) external returns (bool);

    function __constructor__(address _owner, IOptimismGovernor _governor, IGovernanceToken _votingToken, bytes32 _attestationSchemaUid) external;
}
