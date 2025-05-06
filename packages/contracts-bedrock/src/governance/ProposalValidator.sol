pragma solidity 0.8.15;

import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IGovernanceToken } from "interfaces/governance/IGovernanceToken.sol";
import { IEAS, Attestation } from "src/vendor/eas/IEAS.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract ProposalValidator is Ownable {
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

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

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

    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        ProposalType proposalType
    );

    event ProposalApproved(uint256 indexed proposalId, address indexed approver);

    event ProposalMovedToVote(uint256 indexed proposalId, address indexed executor);

    bytes32 public immutable ATTESTATION_SCHEMA_UID; // { approvedProposer: address, proposalType: uint8 }
    uint256 public minimumVotingPower;
    IOptimismGovernor public governor;
    IGovernanceToken public votingToken;

    mapping(uint256 => ProposalData) private _proposals;

    uint256 private _proposalCounter;

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

    /**
     * @notice Submit a proposal for delegate approval
     * @param targets Target addresses for proposal calls
     * @param values ETH values for proposal calls
     * @param calldatas Function data for proposal calls
     * @param description Description of the proposal
     * @param proposalType Type of the proposal
     * @return proposalId The ID of the submitted proposal
     */
    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType,
        bytes32 attestationUid
    )
        external
        returns (uint256)
    {
        _validateProposal(targets, values, calldatas, proposalType, attestationUid);

        uint256 proposalId = ++_proposalCounter;

        ProposalData storage proposal = _proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.description = description;
        proposal.proposalType = proposalType;
        proposal.inVoting = false;
        proposal.remainingApprovalsRequired = 4; // Hardcoded for now, will change with proposalTypes

        emit ProposalSubmitted(proposalId, msg.sender, targets, values, calldatas, description, proposalType);

        return proposalId;
    }

    /**
     * @notice Approve a proposal (only callable by delegates with sufficient voting power)
     * @param proposalId The ID of the proposal to approve
     */
    function approveProposal(uint256 proposalId) external {
        if (!canSignOff(msg.sender)) {
            revert ProposalValidator_InsufficientVotingPower();
        }

        ProposalData storage proposal = _proposals[proposalId];

        if (proposal.delegateApprovals[msg.sender]) {
            revert ProposalValidator_AlreadyApproved();
        }

        proposal.delegateApprovals[msg.sender] = true;
        proposal.remainingApprovalsRequired--; // Expected overflow when all approvals are granted

        emit ProposalApproved(proposalId, msg.sender);
    }

    /**
     * @notice Move a proposal to voting phase after sufficient delegate approvals
     * @param proposalId The ID of the proposal to move to vote
     * @return The proposal ID in the governor contract
     */
    function moveToVote(uint256 proposalId) external returns (uint256) {
        ProposalData storage proposal = _proposals[proposalId];

        if (proposal.remainingApprovalsRequired > 0) {
            revert ProposalValidator_InsufficientApprovals();
        }

        if (proposal.inVoting) {
            revert ProposalValidator_AlreadyProposed();
        }

        proposal.inVoting = true;

        uint256 governorProposalId = governor.propose(
            proposal.targets, proposal.values, proposal.calldatas, proposal.description, uint8(proposal.proposalType)
        );

        emit ProposalMovedToVote(proposalId, msg.sender);

        return governorProposalId;
    }

    /// @notice Returns whether a delegate has enough voting power to vote on a proposal
    function canSignOff(address _delegate) public view returns (bool) {
        return votingToken.balanceOf(_delegate) >= minimumVotingPower;
    }

    function setMinimumVotingPower(uint256 _minimumVotingPower) external onlyOwner {
        minimumVotingPower = _minimumVotingPower;
    }

    /**
     * @notice Sets the voting token used to determine voting power
     * @param _votingToken The token used for determining voting power
     */
    function setVotingToken(IGovernanceToken _votingToken) external onlyOwner {
        votingToken = _votingToken;
    }

    function _validateProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        ProposalType proposalType,
        bytes32 attestationUid
    )
        internal
        view
    {
        if (_requiresApproval(proposalType)) {
            Attestation memory attestation = IEAS(Predeploys.EAS).getAttestation(attestationUid);
            if (
                attestation.attester != owner() || attestation.schema != ATTESTATION_SCHEMA_UID
                    || !_isValidAttestationData(attestation.data, proposalType)
            ) {
                revert ProposalValidator_InvalidAttestation();
            }
        }
    }

    function _requiresApproval(ProposalType proposalType) internal pure returns (bool) {
        return proposalType == ProposalType.ProtocolOrGovernorUpgrade
            || proposalType == ProposalType.MaintenanceUpgradeProposals
            || proposalType == ProposalType.CouncilMemberElections;
    }

    function _isValidAttestationData(
        bytes memory data,
        ProposalType expectedProposalType
    )
        internal
        view
        returns (bool)
    {
        (address approvedDelegate, uint8 proposalType) = abi.decode(data, (address, uint8));
        return approvedDelegate == msg.sender && proposalType == uint8(expectedProposalType);
    }
}
