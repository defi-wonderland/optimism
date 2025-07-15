// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IProposalTypesConfigurator } from "interfaces/governance/IProposalTypesConfigurator.sol";
import {
    IEAS, AttestationRequest, AttestationRequestData, Attestation, RevocationRequest
} from "src/vendor/eas/IEAS.sol";
import { ISchemaRegistry, ISchemaResolver, SchemaRecord } from "src/vendor/eas/ISchemaRegistry.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockEAS } from "./utils/MockEAS.sol";
import { MockGovernor } from "./utils/MockGovernor.sol";
import { Test } from "forge-std/Test.sol";

import { MockProposalTypesConfigurator } from "./utils/MockProposalTypesConfigurator.sol";

/// @title ProposalValidatorForTest
/// @notice Test version of ProposalValidator that exposes internal functions
contract ProposalValidatorForTest is ProposalValidator {
    constructor(
        bytes32 _approvedProposerAttestationSchemaUid,
        bytes32 _topDelegatesAttestationSchemaUid,
        IOptimismGovernor _governor
    )
        ProposalValidator(_approvedProposerAttestationSchemaUid, _topDelegatesAttestationSchemaUid, _governor)
    { }

    /// @notice Exposes proposal data for testing invariants
    function getProposalData(bytes32 _proposalHash)
        public
        view
        returns (
            address proposer_,
            ProposalType proposalType_,
            bool movedToVote_,
            uint256 approvalCount_,
            uint256 votingCycle_
        )
    {
        ProposalData storage proposal = _proposals[_proposalHash];
        return (
            proposal.proposer, proposal.proposalType, proposal.movedToVote, proposal.approvalCount, proposal.votingCycle
        );
    }
}

contract Setup is Test {
    address public owner;
    address public user;
    address public topDelegate_A;
    address public topDelegate_B;
    address public approvedProposer;
    address public votingModule;

    IOptimismGovernor public governor;
    IProposalTypesConfigurator public proposalTypesConfigurator;
    bytes32 public APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID = bytes32(hex"1234");
    bytes32 public TOP_DELEGATES_ATTESTATION_SCHEMA_UID = bytes32(hex"4567");

    uint256 public constant START_TIMESTAMP = 1000000;
    uint256 public constant DURATION = 1 days;
    uint256 public constant DISTRIBUTION_LIMIT = 20000 ether;
    uint256 public constant DISTRIBUTION_THRESHOLD = 10000 ether;
    uint256 public constant PROPOSAL_REQUIRED_APPROVALS = 1;
    uint8 public constant APPROVAL_VOTING_MODULE_ID = 1;
    uint8 public constant OPTIMISTIC_VOTING_MODULE_ID = 2;

    ProposalValidatorForTest public validator;
    ProposalValidatorForTest public impl;

    // Mock contracts
    MockEAS public mockEAS = MockEAS(Predeploys.EAS);

    // Ghost variables to track proposal state
    uint256 public ghost_submittedProposalCount;
    uint256 public ghost_approvedProposalCount;
    uint256 public ghost_movedToVoteCount;
    mapping(ProposalValidator.ProposalType => uint256) public ghost_proposalsByType;
    mapping(bytes32 => bool) public ghost_proposalExists;
    mapping(bytes32 => bool) public ghost_proposalApproved;
    mapping(bytes32 => bool) public ghost_proposalMovedToVote;
    uint256 public ghost_totalTokensRequested;

    // Additional ghost variables for invariants
    mapping(uint256 => uint256) public ghost_fundingAmountMovedToVotePerCycle; // cycle => total amount
    mapping(bytes32 => uint256) public ghost_proposalApprovalCount; // proposal => actual approval count
    mapping(bytes32 => address) public ghost_originalProposer; // proposal => original proposer
    mapping(bytes32 => ProposalValidator.ProposalType) public ghost_originalProposalType; // proposal => original type
    mapping(bytes32 => uint256) public ghost_proposalVotingCycle; // proposal => voting cycle

    function setUp() public virtual {
        owner = makeAddr("owner");
        user = makeAddr("user");
        topDelegate_A = makeAddr("topDelegate_A");
        topDelegate_B = makeAddr("topDelegate_B");
        approvedProposer = makeAddr("approvedProposer");
        votingModule = makeAddr("votingModule");

        ProposalValidator.ProposalType[] memory proposalTypes = new ProposalValidator.ProposalType[](5);
        proposalTypes[0] = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        proposalTypes[1] = ProposalValidator.ProposalType.MaintenanceUpgrade;
        proposalTypes[2] = ProposalValidator.ProposalType.CouncilMemberElections;
        proposalTypes[3] = ProposalValidator.ProposalType.GovernanceFund;
        proposalTypes[4] = ProposalValidator.ProposalType.CouncilBudget;

        ProposalValidator.ProposalTypeData[] memory proposalTypesData =
            new ProposalValidator.ProposalTypeData[](proposalTypes.length);

        // ProtocolOrGovernorUpgrade
        proposalTypesData[0] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: OPTIMISTIC_VOTING_MODULE_ID
        });
        // MaintenanceUpgrade
        proposalTypesData[1] = ProposalValidator.ProposalTypeData({
            requiredApprovals: 0,
            proposalVotingModule: OPTIMISTIC_VOTING_MODULE_ID
        });
        // CouncilMemberElections
        proposalTypesData[2] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: APPROVAL_VOTING_MODULE_ID
        });
        // GovernanceFund
        proposalTypesData[3] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: APPROVAL_VOTING_MODULE_ID
        });
        // CouncilBudget
        proposalTypesData[4] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: APPROVAL_VOTING_MODULE_ID
        });

        governor = IOptimismGovernor(address(new MockGovernor()));

        validator = ProposalValidatorForTest(address(new Proxy(owner)));

        impl = new ProposalValidatorForTest(
            APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID, TOP_DELEGATES_ATTESTATION_SCHEMA_UID, governor
        );

        proposalTypesConfigurator = IProposalTypesConfigurator(address(new MockProposalTypesConfigurator(votingModule)));

        vm.prank(owner);
        IProxy(payable(address(validator))).upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                impl.initialize,
                (
                    owner,
                    proposalTypesConfigurator,
                    1,
                    START_TIMESTAMP,
                    DURATION,
                    DISTRIBUTION_LIMIT,
                    DISTRIBUTION_THRESHOLD,
                    proposalTypes,
                    proposalTypesData
                )
            )
        );

        // Warp to voting cycle start
        vm.warp(START_TIMESTAMP + 1);

        // set a second voting cycle
        vm.prank(owner);
        validator.setVotingCycleData(2, START_TIMESTAMP + DURATION * 2, DURATION, DISTRIBUTION_LIMIT);
    }

    /// @notice Helper to update ghost variables when a proposal is submitted
    function _updateGhostOnSubmit(bytes32 _proposalHash, ProposalValidator.ProposalType _proposalType) internal {
        _updateGhostOnSubmitWithProposer(_proposalHash, _proposalType, msg.sender);
    }

    function _updateGhostOnSubmitWithProposer(
        bytes32 _proposalHash,
        ProposalValidator.ProposalType _proposalType,
        address _proposer
    )
        internal
    {
        ghost_submittedProposalCount++;
        ghost_proposalsByType[_proposalType]++;
        ghost_proposalExists[_proposalHash] = true;

        // Track original proposer and type (immutable after submission)
        ghost_originalProposer[_proposalHash] = _proposer;
        ghost_originalProposalType[_proposalHash] = _proposalType;
    }

    /// @notice Helper to update ghost variables when a proposal is approved
    function _updateGhostOnApprove(bytes32 _proposalHash) internal {
        if (!ghost_proposalApproved[_proposalHash]) {
            ghost_approvedProposalCount++;
            ghost_proposalApproved[_proposalHash] = true;
        }
        // Increment actual approval count
        ghost_proposalApprovalCount[_proposalHash]++;
    }

    /// @notice Helper to update ghost variables when a proposal is moved to vote
    function _updateGhostOnMoveToVote(bytes32 _proposalHash) internal {
        if (!ghost_proposalMovedToVote[_proposalHash]) {
            ghost_movedToVoteCount++;
            ghost_proposalMovedToVote[_proposalHash] = true;
        }
    }

    /// @notice Helper to update ghost variables for token requests
    function _updateGhostTokensRequested(uint256 _amount) internal {
        ghost_totalTokensRequested += _amount;
    }

    /// @notice Helper to update ghost variables when funding proposals move to vote
    function _updateGhostFundingMovedToVote(bytes32 _proposalHash, uint256 _amount, uint256 _cycle) internal {
        ProposalValidator.ProposalType proposalType = ghost_originalProposalType[_proposalHash];
        if (
            proposalType == ProposalValidator.ProposalType.GovernanceFund
                || proposalType == ProposalValidator.ProposalType.CouncilBudget
        ) {
            ghost_fundingAmountMovedToVotePerCycle[_cycle] += _amount;
        }
    }

    /// @notice Helper to track proposal voting cycle
    function _updateGhostProposalVotingCycle(bytes32 _proposalHash, uint256 _cycle) internal {
        ghost_proposalVotingCycle[_proposalHash] = _cycle;
    }
}
