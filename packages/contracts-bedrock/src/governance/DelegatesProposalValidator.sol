
pragma solidity 0.8.15;

import {IDelegatesProposalValidator} from "interfaces/governance/IDelegatesProposalValidator.sol";
import {IOptimismGovernor} from "interfaces/governance/IOptimismGovernor.sol";
import {VotingModule} from "src/governance/VotingModule.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernanceToken} from "interfaces/governance/IGovernanceToken.sol";

contract DelegatesProposalValidator is IDelegatesProposalValidator, Ownable {
    uint256 public minimumVotingPower;
    IOptimismGovernor public governor;
    IGovernanceToken public votingToken;
    
    mapping(uint256 => ProposalData) private _proposals;
    
    uint256 private _proposalCounter;

    constructor(address _owner, IOptimismGovernor _governor, IGovernanceToken _votingToken) {
        transferOwnership(_owner);
        governor = _governor;
        votingToken = _votingToken;
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
        uint8 proposalType
    ) external returns (uint256) {
        uint256 proposalId = ++_proposalCounter;
        
        ProposalData storage proposal = _proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.description = description;
        proposal.proposalType = proposalType;
        proposal.inVoting = false;
        proposal.approvalCount = 0;
        
        emit ProposalSubmitted(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            description,
            proposalType
        );
        
        return proposalId;
    }

    /**
     * @notice Approve a proposal (only callable by delegates with sufficient voting power)
     * @param proposalId The ID of the proposal to approve
     */
    function approveProposal(uint256 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        
        proposal.delegateApprovals[msg.sender] = true;
        proposal.approvalCount++;
        
        emit ProposalApproved(proposalId, msg.sender);
    }

    /**
     * @notice Move a proposal to voting phase after sufficient delegate approvals
     * @param proposalId The ID of the proposal to move to vote
     * @return The proposal ID in the governor contract
     */
    function moveToVote(uint256 proposalId) external returns (uint256) {
        ProposalData storage proposal = _proposals[proposalId];
        
        proposal.inVoting = true;
        
        uint256 governorProposalId = governor.propose(
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            proposal.description,
            proposal.proposalType
        );
        
        emit ProposalMovedToVote(proposalId, msg.sender);
        
        return governorProposalId;
    }

    function propose(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, string memory _description, uint8 _proposalType) external returns (uint256) {
        return governor.propose(_targets, _values, _calldatas, _description, _proposalType);
    }

    function proposeWithModule(VotingModule _module, bytes memory _proposalData, string memory _description, uint8 _proposalType) external returns (uint256) {
        return governor.proposeWithModule(_module, _proposalData, _description, _proposalType);
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
}