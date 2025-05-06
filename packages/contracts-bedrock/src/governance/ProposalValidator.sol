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
     * @param _targets Target addresses for proposal calls
     * @param _values ETH values for proposal calls
     * @param _calldatas Function data for proposal calls
     * @param _description Description of the proposal
     * @param _proposalType Type of the proposal
     * @return proposalId_ The ID of the submitted proposal
     */
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

    /**
     * @notice Approve a proposal (only callable by delegates with sufficient voting power)
     * @param _proposalId The ID of the proposal to approve
     */
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

    /**
     * @notice Move a proposal to voting phase after sufficient delegate approvals
     * @param _proposalId The ID of the proposal to move to vote
     * @return governorProposalId_ The proposal ID in the governor contract
     */
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

    /// @notice Returns whether a delegate has enough voting power to vote on a proposal
    function canSignOff(address _delegate) public view returns (bool canSignOff_) {
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

    function _requiresApproval(ProposalType _proposalType) internal pure returns (bool requiresApproval_) {
        return _proposalType == ProposalType.ProtocolOrGovernorUpgrade
            || _proposalType == ProposalType.MaintenanceUpgradeProposals
            || _proposalType == ProposalType.CouncilMemberElections;
    }

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
