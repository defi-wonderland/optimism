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

import { MockGovernor } from "./utils/MockGovernor.sol";

import { Test } from "forge-std/Test.sol";

/// @title MockSchemaRegistry
/// @notice Simple mock for schema registry that just returns incrementing UIDs
contract MockSchemaRegistry is ISchemaRegistry {
    uint256 private _uidCounter = 1;
    mapping(bytes32 => bool) public schemas;

    function register(string calldata, ISchemaResolver, bool) external returns (bytes32) {
        bytes32 uid = bytes32(_uidCounter++);
        schemas[uid] = true;
        return uid;
    }

    function getSchema(bytes32) external pure returns (SchemaRecord memory) {
        return SchemaRecord({ uid: bytes32(0), resolver: ISchemaResolver(address(0)), revocable: false, schema: "" });
    }
}

/// @title MockEAS
/// @notice Simple mock for EAS that stores attestations - only implements needed methods
contract MockEAS {
    uint256 private _uidCounter = 1;
    mapping(bytes32 => Attestation) public attestations;

    function getSchemaRegistry() external pure returns (ISchemaRegistry) {
        return ISchemaRegistry(address(0));
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32) {
        bytes32 uid = bytes32(_uidCounter++);

        attestations[uid] = Attestation({
            uid: uid,
            schema: request.schema,
            time: uint64(block.timestamp),
            expirationTime: request.data.expirationTime,
            revocationTime: 0,
            refUID: request.data.refUID,
            recipient: request.data.recipient,
            attester: msg.sender,
            revocable: request.data.revocable,
            data: request.data.data
        });

        return uid;
    }

    function revoke(RevocationRequest calldata request) external payable {
        bytes32 uid = request.data.uid;
        require(attestations[uid].attester == msg.sender, "Only attester can revoke");
        attestations[uid].revocationTime = uint64(block.timestamp);
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return attestations[uid];
    }

    function isAttestationValid(bytes32 uid) external view returns (bool) {
        return attestations[uid].uid != bytes32(0) && attestations[uid].revocationTime == 0;
    }
}

contract Setup is Test {
    address public owner;
    address public user;
    address public topDelegate_A;
    address public topDelegate_B;
    address public approvedProposer;
    address public approvalVotingModule;
    address public optimisticVotingModule;

    IOptimismGovernor public governor;
    IProposalTypesConfigurator public proposalTypesConfigurator;
    bytes32 public APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID;
    bytes32 public TOP_DELEGATES_ATTESTATION_SCHEMA_UID;

    uint256 public constant CYCLE_NUMBER = 1;
    uint256 public constant START_TIMESTAMP = 1000000;
    uint256 public constant DURATION = 1 days;
    uint256 public constant DISTRIBUTION_LIMIT = 20000 ether;
    uint256 public constant DISTRIBUTION_THRESHOLD = 10000 ether;
    uint256 public constant PROPOSAL_REQUIRED_APPROVALS = 1;
    uint8 public constant APPROVAL_VOTING_MODULE_ID = 1;
    uint8 public constant OPTIMISTIC_VOTING_MODULE_ID = 2;

    ProposalValidator public validator;
    ProposalValidator public impl;

    // Mock contracts
    MockSchemaRegistry public mockSchemaRegistry;
    MockEAS public mockEAS;

    // Ghost variables to track proposal state
    uint256 public ghost_submittedProposalCount;
    uint256 public ghost_approvedProposalCount;
    uint256 public ghost_movedToVoteCount;
    mapping(ProposalValidator.ProposalType => uint256) public ghost_proposalsByType;
    mapping(bytes32 => bool) public ghost_proposalExists;
    mapping(bytes32 => bool) public ghost_proposalApproved;
    mapping(bytes32 => bool) public ghost_proposalMovedToVote;
    uint256 public ghost_totalTokensRequested;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        topDelegate_A = makeAddr("topDelegate_A");
        topDelegate_B = makeAddr("topDelegate_B");
        approvedProposer = makeAddr("approvedProposer");
        approvalVotingModule = makeAddr("approvalVotingModule");
        optimisticVotingModule = makeAddr("optimisticVotingModule");

        // Deploy mock contracts
        mockSchemaRegistry = new MockSchemaRegistry();
        mockEAS = new MockEAS();

        // Etch mocks at predeploy addresses
        vm.etch(Predeploys.SCHEMA_REGISTRY, address(mockSchemaRegistry).code);
        vm.etch(Predeploys.EAS, address(mockEAS).code);

        // Create schemas using mocks
        vm.prank(owner);
        APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID = ISchemaRegistry(Predeploys.SCHEMA_REGISTRY).register(
            "address approvedAddress,uint8 proposalType", ISchemaResolver(address(0)), true
        );

        vm.prank(owner);
        TOP_DELEGATES_ATTESTATION_SCHEMA_UID = ISchemaRegistry(Predeploys.SCHEMA_REGISTRY).register(
            "string top100,bool includePartialDelegation,string date", ISchemaResolver(address(0)), true
        );

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
        proposalTypesConfigurator = IProposalTypesConfigurator(makeAddr("proposalTypesConfigurator"));

        // Mock proposalTypesConfigurator calls
        vm.mockCall(
            address(proposalTypesConfigurator),
            abi.encodeCall(IProposalTypesConfigurator.proposalTypes, (APPROVAL_VOTING_MODULE_ID)),
            abi.encode(
                IProposalTypesConfigurator.ProposalType({
                    quorum: 100,
                    approvalThreshold: 100,
                    name: "Approval Voting",
                    description: "Approval Voting Module",
                    module: approvalVotingModule
                })
            )
        );

        vm.mockCall(
            address(proposalTypesConfigurator),
            abi.encodeCall(IProposalTypesConfigurator.proposalTypes, (OPTIMISTIC_VOTING_MODULE_ID)),
            abi.encode(
                IProposalTypesConfigurator.ProposalType({
                    quorum: 100,
                    approvalThreshold: 100,
                    name: "Optimistic Voting",
                    description: "Optimistic Voting Module",
                    module: optimisticVotingModule
                })
            )
        );

        validator = ProposalValidator(address(new Proxy(owner)));

        impl = new ProposalValidator(
            APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID, TOP_DELEGATES_ATTESTATION_SCHEMA_UID, governor
        );

        vm.prank(owner);
        IProxy(payable(address(validator))).upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                impl.initialize,
                (
                    owner,
                    proposalTypesConfigurator,
                    CYCLE_NUMBER,
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
    }

    /// @notice Helper to create a valid attestation for an approved proposer
    function _createApprovedProposerAttestation(
        address _delegate,
        ProposalValidator.ProposalType _proposalType
    )
        internal
        returns (bytes32)
    {
        vm.prank(owner);
        return IEAS(Predeploys.EAS).attest(
            AttestationRequest({
                schema: APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: true,
                    refUID: bytes32(0),
                    data: abi.encode(_delegate, _proposalType),
                    value: 0
                })
            })
        );
    }

    /// @notice Helper to create a valid attestation for a top delegate
    function _createTopDelegateAttestation(address _delegate) internal returns (bytes32) {
        vm.prank(owner);
        return IEAS(Predeploys.EAS).attest(
            AttestationRequest({
                schema: TOP_DELEGATES_ATTESTATION_SCHEMA_UID,
                data: AttestationRequestData({
                    recipient: _delegate,
                    expirationTime: 0,
                    revocable: true,
                    refUID: bytes32(0),
                    data: abi.encode("top100", false, "2000-01-01"),
                    value: 0
                })
            })
        );
    }

    /// @notice Helper to update ghost variables when a proposal is submitted
    function _updateGhostOnSubmit(bytes32 _proposalHash, ProposalValidator.ProposalType _proposalType) internal {
        ghost_submittedProposalCount++;
        ghost_proposalsByType[_proposalType]++;
        ghost_proposalExists[_proposalHash] = true;
    }

    /// @notice Helper to update ghost variables when a proposal is approved
    function _updateGhostOnApprove(bytes32 _proposalHash) internal {
        if (!ghost_proposalApproved[_proposalHash]) {
            ghost_approvedProposalCount++;
            ghost_proposalApproved[_proposalHash] = true;
        }
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
}
