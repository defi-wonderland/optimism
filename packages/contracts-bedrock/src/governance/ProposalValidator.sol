pragma solidity 0.8.15;

import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IGovernanceToken } from "interfaces/governance/IGovernanceToken.sol";
import { IEAS, Attestation } from "src/vendor/eas/IEAS.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract ProposalValidator is OwnableUpgradeable {
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

    event ProposalApproved(bytes32 indexed proposalHash, address indexed approver);

    event ProposalMovedToVote(bytes32 indexed proposalHash, address indexed executor);

    bytes32 public immutable ATTESTATION_SCHEMA_UID; // { approvedDelegate: address, proposalType: uint8 }
    uint256 public minimumVotingPower;
    IOptimismGovernor public governor;
    IGovernanceToken public votingToken;

    mapping(bytes32 => ProposalData) private _proposals;

    constructor(
        bytes32 _attestationSchemaUid
    ) {
        ATTESTATION_SCHEMA_UID = _attestationSchemaUid;
        _disableInitializers();
    }

    function initialize(
        IOptimismGovernor _governor,
        IGovernanceToken _votingToken,
        uint256 _minimumVotingPower,
        address _owner
    )
        external
        initializer
    {
        governor = _governor;
        votingToken = _votingToken;
        minimumVotingPower = _minimumVotingPower;
        __Ownable_init();
        _transferOwnership(_owner);
    }

    /**
     * @notice Submit a proposal for delegate approval
     * @param targets Target addresses for proposal calls
     * @param values ETH values for proposal calls
     * @param calldatas Function data for proposal calls
     * @param description Description of the proposal
     * @param proposalType Type of the proposal
     * @return proposalHash_ The hash of the submitted proposal
     */
    function submitProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType,
        uint8 proposalTypeConfigurator,
        bytes32 attestationUid
    )
        external
        returns (bytes32 proposalHash_)
    {
        _validateProposal(targets, values, calldatas, proposalType, attestationUid);

        proposalHash_ = _hashProposal(targets, values, calldatas, description);
        ProposalData storage proposal = _proposals[proposalHash_];

        if (proposal.proposer != address(0)) {
            revert ProposalValidator_AlreadyProposed();
        }

        proposal.proposer = msg.sender;
        proposal.proposalType = proposalType;
        proposal.proposalTypeConfigurator = proposalTypeConfigurator;
        proposal.inVoting = false;
        proposal.remainingApprovalsRequired = 4; // Hardcoded for now, will change with proposalTypes

        emit ProposalSubmitted(
            proposalHash_, msg.sender, targets, values, calldatas, description, proposalType, proposalTypeConfigurator
        );
    }

    /**
     * @notice Approve a proposal (only callable by delegates with sufficient voting power)
     * @param proposalHash The hash of the proposal to approve
     */
    function approveProposal(bytes32 proposalHash) external {
        if (!canSignOff(msg.sender)) {
            revert ProposalValidator_InsufficientVotingPower();
        }

        ProposalData storage proposal = _proposals[proposalHash];

        if (proposal.delegateApprovals[msg.sender]) {
            revert ProposalValidator_AlreadyApproved();
        }

        proposal.delegateApprovals[msg.sender] = true;
        proposal.remainingApprovalsRequired--; // Expected overflow when all approvals are granted

        emit ProposalApproved(proposalHash, msg.sender);
    }

    /**
     * @notice Move a proposal to voting phase after sufficient delegate approvals
     * @param targets Target addresses for proposal calls
     * @param values ETH values for proposal calls
     * @param calldatas Function data for proposal calls
     * @param description Description of the proposal
     * @return The proposal ID in the governor contract
     */
    function moveToVote(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    )
        external
        returns (uint256)
    {
        // Verify that the provided data matches the proposalHash
        bytes32 _proposalHash = _hashProposal(targets, values, calldatas, description);

        ProposalData storage proposal = _proposals[_proposalHash];

        if (proposal.proposer == address(0)) {
            revert ProposalValidator_UnexistentProposal();
        }

        if (proposal.remainingApprovalsRequired > 0) {
            revert ProposalValidator_InsufficientApprovals();
        }

        if (proposal.inVoting) {
            revert ProposalValidator_AlreadyProposed();
        }

        proposal.inVoting = true;

        uint256 governorProposalId =
            governor.propose(targets, values, calldatas, description, uint8(proposal.proposalType));

        emit ProposalMovedToVote(_proposalHash, msg.sender);

        return governorProposalId;
    }

    /// @notice Returns whether a delegate has enough voting power to vote on a proposal
    function canSignOff(address _delegate) public view returns (bool) {
        return votingToken.balanceOf(_delegate) >= minimumVotingPower;
    }

    function setMinimumVotingPower(uint256 _minimumVotingPower) external onlyOwner {
        minimumVotingPower = _minimumVotingPower;
    }

    function setProposalThreshold(uint256 _newProposalThreshold) external onlyOwner {
        governor.setProposalThreshold(_newProposalThreshold);
    }

    function setProposalDeadline(uint256 _proposalId, uint64 _deadline) external onlyOwner {
        governor.setProposalDeadline(_proposalId, _deadline);
    }

    function setVotingDelay(uint256 _newVotingDelay) external onlyOwner {
        governor.setVotingDelay(_newVotingDelay);
    }

    function setVotingPeriod(uint256 _newVotingPeriod) external onlyOwner {
        governor.setVotingPeriod(_newVotingPeriod);
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

    function _hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(targets, values, calldatas, description));
    }
}
