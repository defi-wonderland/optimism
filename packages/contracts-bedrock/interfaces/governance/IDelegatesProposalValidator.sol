// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VotingModule} from "src/governance/VotingModule.sol";
import {IOptimismGovernor} from "./IOptimismGovernor.sol";

interface IDelegatesProposalValidator {
    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    function governor() external view returns (IOptimismGovernor);
    function minimumVotingPower() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) external returns (uint256 proposalId);

    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) external returns (uint256 proposalId);

    function setMinimumVotingPower(uint256 minimumVotingPower) external;

    function setProposalDeadline(uint256 proposalId, uint64 deadline) external;
    
    function setVotingDelay(uint256 newVotingDelay) external;
    
    function setVotingPeriod(uint256 newVotingPeriod) external;
    
    function setProposalThreshold(uint256 newProposalThreshold) external;
}
