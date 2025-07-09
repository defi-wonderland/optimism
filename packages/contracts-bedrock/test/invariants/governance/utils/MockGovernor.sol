// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract MockGovernor is IOptimismGovernor {
    mapping(uint256 => bool) public proposalExists;
    mapping(uint256 => uint8) public proposalTypeMapping;

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    )
        external
        returns (uint256 proposalId)
    {
        // Create a simple hash as proposal ID
        proposalId =
            uint256(keccak256(abi.encode(targets, values, calldatas, description, proposalType, block.timestamp)));
        proposalExists[proposalId] = true;
        proposalTypeMapping[proposalId] = proposalType;
        return proposalId;
    }

    function proposeWithModule(
        address module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    )
        external
        returns (uint256 proposalId)
    {
        // Generate proposal ID based on inputs - should match validator's _hashProposalWithModule
        proposalId = uint256(keccak256(abi.encode(address(this), module, proposalData, keccak256(bytes(description)))));
        proposalExists[proposalId] = true;
        proposalTypeMapping[proposalId] = proposalType;
        return proposalId;
    }

    function timelock() external view returns (address) {
        return address(0);
    }

    function PROPOSAL_TYPES_CONFIGURATOR() external view returns (address) {
        return address(0);
    }

    function token() external view returns (IVotesUpgradeable) {
        return IVotesUpgradeable(address(0));
    }

    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return proposalTypeMapping[proposalId];
    }

    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        return (0, 0, 0);
    }

    function proposalSnapshot(uint256 proposalId) external view returns (uint256) {
        // Return non-zero only if proposal exists (was created)
        return proposalExists[proposalId] ? 1 : 0;
    }
}
