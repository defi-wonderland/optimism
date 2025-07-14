// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IProposalTypesConfigurator } from "interfaces/governance/IProposalTypesConfigurator.sol";

contract MockProposalTypesConfigurator {
    address public votingModule;

    constructor(address _votingModule) {
        votingModule = _votingModule;
    }

    function proposalTypes(uint8 proposalTypeId)
        external
        view
        returns (IProposalTypesConfigurator.ProposalType memory)
    {
        return IProposalTypesConfigurator.ProposalType({
            quorum: 0,
            approvalThreshold: 0,
            name: "",
            description: "",
            module: votingModule
        });
    }
}
