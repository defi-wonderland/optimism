// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegatesProposalValidator} from "interfaces/governance/IDelegatesProposalValidator.sol";
import {IOptimismGovernor} from "@optimism-governor/interfaces/IOptimismGovernor.sol";
import {VotingModule} from "@optimism-governor/modules/VotingModule.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IOptimismGovernorWithModule {
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description, uint8 proposalType) external returns (uint256);
    function setProposalDeadline(uint256 proposalId, uint64 deadline) external;
    function setVotingDelay(uint256 newVotingDelay) external;
    function setVotingPeriod(uint256 newVotingPeriod) external;
    function setProposalThreshold(uint256 newProposalThreshold) external;
}

contract DelegatesProposalValidator is IDelegatesProposalValidator, Ownable {
    uint256 public minimumVotingPower;
    uint256 public proposalThreshold;
    IOptimismGovernor public governor;

    constructor(address _owner, IOptimismGovernor _governor) {
        transferOwnership(_owner);
        governor = _governor;
    }

    function propose(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, string memory _description) external returns (uint256) {
        return governor.propose(_targets, _values, _calldatas, _description);
    }

    function proposeWithModule(VotingModule _module, bytes memory _proposalData, string memory _description, uint8 _proposalType) external returns (uint256) {
        return IOptimismGovernorWithModule(address(governor)).proposeWithModule(_module, _proposalData, _description, _proposalType);
    }   

    function setMinimumVotingPower(uint256 _minimumVotingPower) external onlyOwner {
        minimumVotingPower = _minimumVotingPower;
    }   

    function setProposalThreshold(uint256 _newProposalThreshold) external onlyOwner {
        proposalThreshold = _newProposalThreshold;
    }

    function setProposalDeadline(uint256 _proposalId, uint64 _deadline) external onlyOwner {
        IOptimismGovernorWithModule(address(governor)).setProposalDeadline(_proposalId, _deadline);
    }

    function setVotingDelay(uint256 _newVotingDelay) external onlyOwner {
        IOptimismGovernorWithModule(address(governor)).setVotingDelay(_newVotingDelay);
    }

    function setVotingPeriod(uint256 _newVotingPeriod) external onlyOwner {
        IOptimismGovernorWithModule(address(governor)).setVotingPeriod(_newVotingPeriod);
    }
}