// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IGovernanceToken } from "interfaces/governance/IGovernanceToken.sol";
import { IEAS, Attestation } from "src/vendor/eas/IEAS.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title ProposalValidator
/// @notice The ProposalValidator contract is responsible for validating proposals and moving
///         them to the vote phase on the Optimism Governor.
contract ProposalValidator is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a proposal doesn't have enough delegate approvals to move to vote.
    error ProposalValidator_InsufficientApprovals();

    /// @notice Thrown when a delegate attempts to approve a proposal they've already approved.
    error ProposalValidator_AlreadyApproved();

    /// @notice Thrown when attempting to move a proposal to vote that is already in voting.
    error ProposalValidator_AlreadyProposed();

    /// @notice Thrown when a delegate has insufficient voting power to approve a proposal.
    error ProposalValidator_InsufficientVotingPower();

    /// @notice Thrown when an invalid attestation is provided for a proposal.
    error ProposalValidator_InvalidAttestation();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Data structure for storing proposal information.
    /// @param proposer The address that submitted the proposal.
    /// @param targets Target addresses for proposal calls.
    /// @param values ETH values for proposal calls.
    /// @param calldatas Function data for proposal calls.
    /// @param description Description of the proposal.
    /// @param proposalType Type of the proposal from the ProposalType enum.
    /// @param inVoting Whether the proposal has been moved to the voting phase.
    /// @param delegateApprovals Mapping of delegate addresses to their approval status.
    /// @param remainingApprovalsRequired Number of approvals still needed before voting.
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

    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Types of proposals that can be submitted.
    /// @param ProtocolOrGovernorUpgrade Proposals for upgrading the protocol or governor.
    /// @param MaintenanceUpgradeProposals Proposals for maintenance upgrades.
    /// @param CouncilMemberElections Proposals for council member elections.
    /// @param GovernanceFund Proposals related to the governance fund.
    /// @param CouncilBudget Proposals related to the council budget.
    enum ProposalType {
        ProtocolOrGovernorUpgrade,
        MaintenanceUpgradeProposals,
        CouncilMemberElections,
        GovernanceFund,
        CouncilBudget
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new proposal is submitted.
    /// @param proposalId The ID of the submitted proposal.
    /// @param proposer The address that submitted the proposal.
    /// @param targets Target addresses for proposal calls.
    /// @param values ETH values for proposal calls.
    /// @param calldatas Function data for proposal calls.
    /// @param description Description of the proposal.
    /// @param proposalType Type of the proposal.
    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        ProposalType proposalType
    );

    /// @notice Emitted when a delegate approves a proposal.
    /// @param proposalId The ID of the approved proposal.
    /// @param approver The address of the delegate who approved the proposal.
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);

    /// @notice Emitted when a proposal is moved to the voting phase.
    /// @param proposalId The ID of the proposal moved to vote.
    /// @param executor The address that executed the move to vote.
    event ProposalMovedToVote(uint256 indexed proposalId, address indexed executor);

    /// @notice The schema UID for attestations in the Ethereum Attestation Service.
    /// @dev Schema format: { approvedProposer: address, proposalType: uint8 }
    bytes32 public immutable ATTESTATION_SCHEMA_UID;

    /// @notice The minimum voting power required for a delegate to approve proposals.
    uint256 public minimumVotingPower;

    /// @notice The Optimism Governor contract that will handle the voting phase.
    IOptimismGovernor public governor;

    /// @notice The token used to determine voting power.
    IGovernanceToken public votingToken;

    /// @notice Mapping of proposal IDs to their corresponding proposal data.
    mapping(uint256 => ProposalData) private _proposals;

    /// @notice Counter for generating unique proposal IDs.
    uint256 private _proposalCounter;

    /// @notice Initializes the ProposalValidator contract.
    /// @param _owner The address that will own the contract.
    /// @param _governor The Optimism Governor contract address.
    /// @param _votingToken The token used to determine voting power.
    /// @param _attestationSchemaUid The schema UID for attestations in EAS.
    constructor(
        address _owner,
        IOptimismGovernor _governor,
        IGovernanceToken _votingToken,
        bytes32 _attestationSchemaUid
    ) {
        transferOwnership(_owner);
        governor = _governor;
        votingToken = _votingToken;
        ATTESTATION_SCHEMA_UID = _attestationSchemaUid;
    }

    /// @notice Submit a proposal for delegate approval.
    /// @param _targets Target addresses for proposal calls.
    /// @param _values ETH values for proposal calls.
    /// @param _calldatas Function data for proposal calls.
    /// @param _description Description of the proposal.
    /// @param _proposalType Type of the proposal.
    /// @param _attestationUid The UID of the attestation proving eligibility.
    /// @return proposalId_ The ID of the submitted proposal.
    function submitProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        ProposalType _proposalType,
        bytes32 _attestationUid
    )
        external
        returns (uint256 proposalId_)
    {
        _validateProposal(_targets, _values, _calldatas, _proposalType, _attestationUid);

        proposalId_ = ++_proposalCounter;

        ProposalData storage proposal = _proposals[proposalId_];
        proposal.proposer = msg.sender;
        proposal.targets = _targets;
        proposal.values = _values;
        proposal.calldatas = _calldatas;
        proposal.description = _description;
        proposal.proposalType = _proposalType;
        proposal.inVoting = false;
        proposal.remainingApprovalsRequired = 4; // Hardcoded for now, will change with proposalTypes

        emit ProposalSubmitted(proposalId_, msg.sender, _targets, _values, _calldatas, _description, _proposalType);

        return proposalId_;
    }

    /// @notice Approve a proposal (only callable by delegates with sufficient voting power).
    /// @param _proposalId The ID of the proposal to approve.
    function approveProposal(uint256 _proposalId) external {
        if (!canSignOff(msg.sender)) {
            revert ProposalValidator_InsufficientVotingPower();
        }

        ProposalData storage proposal = _proposals[_proposalId];

        if (proposal.delegateApprovals[msg.sender]) {
            revert ProposalValidator_AlreadyApproved();
        }

        proposal.delegateApprovals[msg.sender] = true;
        proposal.remainingApprovalsRequired--; // Expected overflow when all approvals are granted

        emit ProposalApproved(_proposalId, msg.sender);
    }

    /// @notice Move a proposal to voting phase after sufficient delegate approvals.
    /// @param _proposalId The ID of the proposal to move to vote.
    /// @return governorProposalId_ The proposal ID in the governor contract.
    function moveToVote(uint256 _proposalId) external returns (uint256 governorProposalId_) {
        ProposalData storage proposal = _proposals[_proposalId];

        if (proposal.remainingApprovalsRequired > 0) {
            revert ProposalValidator_InsufficientApprovals();
        }

        if (proposal.inVoting) {
            revert ProposalValidator_AlreadyProposed();
        }

        proposal.inVoting = true;

        governorProposalId_ = governor.propose(
            proposal.targets, proposal.values, proposal.calldatas, proposal.description, uint8(proposal.proposalType)
        );

        emit ProposalMovedToVote(_proposalId, msg.sender);

        return governorProposalId_;
    }

    /// @notice Returns whether a delegate has enough voting power to approve a proposal.
    /// @param _delegate The address of the delegate to check.
    /// @return canSignOff_ True if the delegate has sufficient voting power, false otherwise.
    function canSignOff(address _delegate) public view returns (bool canSignOff_) {
        return votingToken.balanceOf(_delegate) >= minimumVotingPower;
    }

    /// @notice Sets the minimum voting power required for a delegate to approve proposals.
    /// @param _minimumVotingPower The new minimum voting power threshold.
    function setMinimumVotingPower(uint256 _minimumVotingPower) external onlyOwner {
        minimumVotingPower = _minimumVotingPower;
    }

    /// @notice Sets the voting token used to determine voting power.
    /// @param _votingToken The token used for determining voting power.
    function setVotingToken(IGovernanceToken _votingToken) external onlyOwner {
        votingToken = _votingToken;
    }

    /// @notice Validates a proposal before submission.
    /// @dev Checks if the proposal requires approval and validates the attestation.
    /// @param _targets Target addresses for proposal calls.
    /// @param _values ETH values for proposal calls.
    /// @param _calldatas Function data for proposal calls.
    /// @param _proposalType Type of the proposal.
    /// @param _attestationUid The UID of the attestation proving eligibility.
    function _validateProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        ProposalType _proposalType,
        bytes32 _attestationUid
    )
        internal
        view
    {
        if (_requiresApproval(_proposalType)) {
            Attestation memory attestation = IEAS(Predeploys.EAS).getAttestation(_attestationUid);
            if (
                attestation.attester != owner() || attestation.schema != ATTESTATION_SCHEMA_UID
                    || !_isValidAttestationData(attestation.data, _proposalType)
            ) {
                revert ProposalValidator_InvalidAttestation();
            }
        }
    }

    /// @notice Determines if a proposal type requires approval via attestation.
    /// @param _proposalType The type of proposal to check.
    /// @return requiresApproval_ True if the proposal type requires approval, false otherwise.
    function _requiresApproval(ProposalType _proposalType) internal pure returns (bool requiresApproval_) {
        return _proposalType == ProposalType.ProtocolOrGovernorUpgrade
            || _proposalType == ProposalType.MaintenanceUpgradeProposals
            || _proposalType == ProposalType.CouncilMemberElections;
    }

    /// @notice Validates the attestation data for a proposal.
    /// @param _data The attestation data to validate.
    /// @param _expectedProposalType The expected proposal type from the attestation.
    /// @return isValid_ True if the attestation data is valid, false otherwise.
    function _isValidAttestationData(
        bytes memory _data,
        ProposalType _expectedProposalType
    )
        internal
        view
        returns (bool isValid_)
    {
        (address approvedDelegate, uint8 proposalType) = abi.decode(_data, (address, uint8));
        return approvedDelegate == msg.sender && proposalType == uint8(_expectedProposalType);
    }
}
