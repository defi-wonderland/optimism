// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IProposalValidator } from "interfaces/governance/IProposalValidator.sol";
import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IEAS, AttestationRequest, AttestationRequestData } from "src/vendor/eas/IEAS.sol";
import { ISchemaRegistry, ISchemaResolver } from "src/vendor/eas/ISchemaRegistry.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

contract ProposalValidator_Test is CommonTest {
    uint256 public constant TOP_DELEGATE_VOTING_POWER = 10000 ether; // 10k OP

    address owner;
    address rando;
    address topDelegate_A;
    address topDelegate_B;
    address topDelegate_C;
    address topDelegate_D;

    ProposalValidator public validator;
    IOptimismGovernor public governor;
    bytes32 public ATTESTATION_SCHEMA_UID;

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

        vm.prank(owner);
        ATTESTATION_SCHEMA_UID = ISchemaRegistry(Predeploys.SCHEMA_REGISTRY).register(
            "address approvedAddress,uint8 proposalType", ISchemaResolver(address(0)), false
        );

        validator = new ProposalValidator(owner, governor, governanceToken, ATTESTATION_SCHEMA_UID);

        vm.prank(owner);
        validator.setMinimumVotingPower(TOP_DELEGATE_VOTING_POWER);

        topDelegate_A = _makeTopDelegate("topDelegate_A");
        topDelegate_B = _makeTopDelegate("topDelegate_B");
        topDelegate_C = _makeTopDelegate("topDelegate_C");
        topDelegate_D = _makeTopDelegate("topDelegate_D");
    }

    function test_proposalFullFlow_succeeds() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = bytes("");
        string memory description = "Test proposal";
        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;

        vm.prank(owner);
        bytes32 attestationUid = IEAS(Predeploys.EAS).attest(
            AttestationRequest({
                schema: ATTESTATION_SCHEMA_UID,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: false,
                    refUID: bytes32(0),
                    data: abi.encode(topDelegate_A, proposalType),
                    value: 0
                })
            })
        );

        vm.prank(topDelegate_A);
        uint256 proposalId =
            validator.submitProposal(targets, values, calldatas, description, proposalType, attestationUid);
        assertEq(proposalId, 1);

        // It reverts when caller is not a top delegate
        vm.expectRevert(IProposalValidator.ProposalValidator_InsufficientVotingPower.selector);
        _approveProposal(rando, proposalId);

        _approveProposal(topDelegate_A, proposalId);
        _approveProposal(topDelegate_B, proposalId);
        _approveProposal(topDelegate_C, proposalId);

        // It reverts when proposal hasn't reached the required approvals
        vm.expectRevert(IProposalValidator.ProposalValidator_InsufficientApprovals.selector);
        vm.prank(owner);
        validator.moveToVote(proposalId);

        _approveProposal(topDelegate_D, proposalId);

        _mockAndExpect(
            address(governor),
            abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, uint8(proposalType))),
            abi.encode(1)
        );

        vm.prank(owner);
        validator.moveToVote(proposalId);

        // It reverts when proposal is already in voting phase
        vm.expectRevert(IProposalValidator.ProposalValidator_AlreadyProposed.selector);
        vm.prank(owner);
        validator.moveToVote(proposalId);
    }
}
