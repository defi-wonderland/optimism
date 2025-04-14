// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegatesProposalValidator} from "interfaces/governance/IDelegatesProposalValidator.sol";
import {IOptimismGovernor} from "interfaces/governance/IOptimismGovernor.sol";
import {VotingModule} from "src/governance/VotingModule.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DelegatesProposalValidator is IDelegatesProposalValidator, Ownable {
    uint256 public minimumVotingPower;
    IOptimismGovernor public governor;

    constructor(address _owner, IOptimismGovernor _governor) {
        transferOwnership(_owner);
        governor = _governor;
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
}