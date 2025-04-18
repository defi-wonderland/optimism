// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {DelegatesProposalValidator} from "src/governance/DelegatesProposalValidator.sol";
import {IOptimismGovernor} from "interfaces/governance/IOptimismGovernor.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

contract DelegatesProposalValidator_Test is CommonTest {
    address owner;
    address rando;
    DelegatesProposalValidator validator;
    IOptimismGovernor governor;

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        owner = governanceToken.owner();
        rando = makeAddr("rando");
        governor = IOptimismGovernor(makeAddr("governor"));

        validator = new DelegatesProposalValidator(owner, governor, governanceToken);
    }

    function test_proposalFullFlow() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);  
        calldatas[0] = bytes("");
        string memory description = "Test proposal";
        uint8 proposalType = 1;

        vm.prank(owner);    
        uint256 proposalId = validator.submitProposal(targets, values, calldatas, description, proposalType);
        assertEq(proposalId, 1);

        // Approve the proposal
        vm.prank(rando);
        validator.approveProposal(proposalId);

        _mockAndExpect(address(governor), abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, proposalType)), abi.encode(1));

        // Move to vote
        vm.prank(owner);
        validator.moveToVote(proposalId);
    }
}
