// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGovernanceToken} from "./IGovernanceToken.sol";
import {IOptimismGovernor} from "./IOptimismGovernor.sol";

/// @title IProposalValidator
/// @notice Interface for the ProposalValidator contract.
interface IProposalValidator {
    error ProposalValidator_InsufficientApprovals();
    error ProposalValidator_AlreadyApproved();
    error ProposalValidator_AlreadyProposed();
    error ProposalValidator_InsufficientVotingPower();
    error ProposalValidator_InvalidAttestation();
    error ProposalValidator_InvalidProposalData();
    error ProposalValidator_UnexistentProposal();

    struct ProposalData {
        address proposer;
        ProposalType proposalType;
        uint8 proposalTypeConfigurator;
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

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event MinimumVotingPowerSet(uint256 newMinimumVotingPower);

    event VotingCycleBlockSet(uint256 newVotingCycleBlock);

    event DistributionThresholdSet(uint256 newDistributionThreshold);

    event ProposalApprovalThresholdSet(ProposalType proposalType, uint256 newApprovalThreshold);

    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType,
        uint8 proposalTypeConfigurator,
        bytes32 attestationUid
    ) external returns (bytes32 proposalHash);

    function approveProposal(bytes32 proposalHash) external;

    function moveToVote(
        bytes32 proposalHash,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 governorProposalId);
    
    function setMinimumVotingPower(uint256 _minimumVotingPower) external;

    function setVotingCycleBlock(uint256 _votingCycleBlock) external;

    function setDistributionThreshold(uint256 _distributionThreshold) external;

    function setProposalRequiredApprovals(ProposalType _proposalType, uint256 _requiredApprovals) external;
    
    function renounceOwnership() external;
    
    function canSignOff(address _delegate) external view returns (bool canSignOff_);
    
    function transferOwnership(address newOwner) external;

    function minimumVotingPower() external view returns (uint256);

    function votingCycleBlock() external view returns (uint256);

    function distributionThreshold() external view returns (uint256);

    function votingToken() external view returns (IGovernanceToken);

    function governor() external view returns (IOptimismGovernor);

    function owner() external view returns (address);

    function ATTESTATION_SCHEMA_UID() external view returns (bytes32);
    
    function __constructor__(        address _owner,
        IOptimismGovernor _governor,
        IGovernanceToken _votingToken,
        bytes32 _attestationSchemaUid,
        uint256 _minimumVotingPower,
        uint256 _votingCycleBlock,
        uint256 _distributionThreshold,
        ProposalType[] memory _proposalTypes,
        uint256[] memory _requiredApprovals) external;
}
