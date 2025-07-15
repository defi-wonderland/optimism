// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IProposalTypesConfigurator } from "interfaces/governance/IProposalTypesConfigurator.sol";

contract MockProposalTypesConfigurator {
    address public votingModule;
    address public optimisticModule;

    constructor(address _votingModule) {
        votingModule = _votingModule;
        optimisticModule = _votingModule; // For simplicity, use same address
    }

    function proposalTypes(uint8 proposalTypeId)
        external
        view
        returns (IProposalTypesConfigurator.ProposalType memory)
    {
        address moduleToUse = (proposalTypeId == 1) ? votingModule : optimisticModule;
        return IProposalTypesConfigurator.ProposalType({
            quorum: 0,
            approvalThreshold: 0,
            name: "",
            description: "",
            module: moduleToUse
        });
    }
}
