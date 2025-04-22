// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IDelegatesProposalValidator} from "interfaces/governance/IDelegatesProposalValidator.sol";
import {DelegatesProposalValidator} from "src/governance/DelegatesProposalValidator.sol";
import {IOptimismGovernor} from "interfaces/governance/IOptimismGovernor.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

contract DelegatesProposalValidator_Test is CommonTest {
    uint256 public constant TOP_DELEGATE_VOTING_POWER = 10000 ether; // 10k OP

    address owner;
    address rando;
    address topDelegate_A;
    address topDelegate_B;
    address topDelegate_C;
    address topDelegate_D;

    DelegatesProposalValidator validator;
    IOptimismGovernor governor;

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    function _makeTopDelegate(string memory _name) internal returns (address) {
        address delegate = makeAddr(_name);
        deal(address(governanceToken), delegate, TOP_DELEGATE_VOTING_POWER);
        vm.prank(delegate);
        governanceToken.delegate(delegate);
        return delegate;
    }

    function _approveProposal(address _delegate, uint256 _proposalId) internal {
        vm.prank(_delegate);
        validator.approveProposal(_proposalId);
    }

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        owner = governanceToken.owner();
        rando = makeAddr("rando");
        governor = IOptimismGovernor(makeAddr("governor"));

        validator = new DelegatesProposalValidator(owner, governor, governanceToken);

        vm.prank(owner);
        validator.setMinimumVotingPower(TOP_DELEGATE_VOTING_POWER);

        topDelegate_A = _makeTopDelegate("topDelegate_A");
        topDelegate_B = _makeTopDelegate("topDelegate_B");
        topDelegate_C = _makeTopDelegate("topDelegate_C");
        topDelegate_D = _makeTopDelegate("topDelegate_D");
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

        // It reverts when caller is not a top delegate
        vm.expectRevert(IDelegatesProposalValidator.DelegatesProposalValidator_InsufficientVotingPower.selector);
        _approveProposal(rando, proposalId);

        _approveProposal(topDelegate_A, proposalId);
        _approveProposal(topDelegate_B, proposalId);
        _approveProposal(topDelegate_C, proposalId);

        // It reverts when proposal hasn't reached the required approvals
        vm.expectRevert(IDelegatesProposalValidator.DelegatesProposalValidator_InsufficientApprovals.selector);
        vm.prank(owner);
        validator.moveToVote(proposalId);

        _approveProposal(topDelegate_D, proposalId);

        _mockAndExpect(address(governor), abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, proposalType)), abi.encode(1));

        vm.prank(owner);
        validator.moveToVote(proposalId);

        // It reverts when proposal is already in voting phase
        vm.expectRevert(IDelegatesProposalValidator.DelegatesProposalValidator_AlreadyProposed.selector);
        vm.prank(owner);
        validator.moveToVote(proposalId);
    }
}
