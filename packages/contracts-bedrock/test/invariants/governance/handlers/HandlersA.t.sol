// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup } from "../Setup.t.sol";
import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { IApprovalVotingModule } from "interfaces/governance/IApprovalVotingModule.sol";
import { IOptimisticModule } from "interfaces/governance/IOptimisticModule.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockEAS } from "../utils/MockEAS.sol";
import { Attestation } from "src/vendor/eas/IEAS.sol";

contract HandlersA is Setup {
    // Arrays to store created proposals for later operations
    bytes32[] public submittedProposals;
    mapping(bytes32 => ProposalValidator.ProposalType) public proposalTypes;
    mapping(bytes32 => address) public proposalProposers;
    mapping(bytes32 => bytes) public proposalVotingModuleData;
    mapping(bytes32 => string) public proposalDescriptions;
    mapping(bytes32 => uint256) public proposalCriteriaValues;
    mapping(bytes32 => string[]) public proposalOptionDescriptions;
    mapping(bytes32 => address[]) public proposalOptionRecipients;
    mapping(bytes32 => uint256[]) public proposalOptionAmounts;
    mapping(bytes32 => uint248) public proposalAgainstThresholds;

    address actor;

    modifier useActor(uint256 actorIndexSeed) {
        actor = _getActor(actorIndexSeed);
        _;
    }

    function handler_submitProtocolOrGovernorUpgradeProposal(
        uint256 actorSeed,
        uint248 againstThreshold,
        uint256 descriptionSeed,
        uint256 votingCycle
    )
        external
        useActor(actorSeed)
    {
        againstThreshold = uint248(bound(againstThreshold, 1, 10000));
        votingCycle = bound(votingCycle, 1, 10);

        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;

        string memory description = string(abi.encodePacked("Protocol Upgrade #", vm.toString(descriptionSeed)));

        mockEAS.forTest_setAttestation(
            bytes32(hex"1234"),
            Attestation({
                uid: bytes32(hex"1234"),
                schema: validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: address(0),
                attester: validator.owner(),
                revocable: false,
                data: abi.encode(actor, uint8(proposalType))
            })
        );

        // Create optimistic module settings
        IOptimisticModule.ProposalSettings memory settings =
            IOptimisticModule.ProposalSettings({ againstThreshold: againstThreshold, isRelativeToVotableSupply: true });

        bytes memory votingModuleData = abi.encode(settings);
        bytes32 proposalHash = _calculateProposalHash(votingModule, votingModuleData, description);

        vm.prank(actor);
        try validator.submitUpgradeProposal(
            againstThreshold, description, bytes32(hex"1234"), proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            submittedProposals.push(returnedHash);
            proposalTypes[returnedHash] = proposalType;
            proposalProposers[returnedHash] = actor;
            proposalVotingModuleData[returnedHash] = votingModuleData;
            proposalDescriptions[returnedHash] = description;
            proposalAgainstThresholds[returnedHash] = againstThreshold;
            _updateGhostOnSubmitWithProposer(returnedHash, proposalType, actor);
            _updateGhostProposalVotingCycle(returnedHash, votingCycle);
        } catch (bytes memory reason) {
            // Expected reverts for upgrade proposals
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidUpgradeProposalType()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidAttestation()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidAgainstThreshold()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadySubmitted()"))
            );
        }
    }

    function handler_submitMaintenanceUpgradeProposal(
        uint256 actorSeed,
        uint248 againstThreshold,
        uint256 descriptionSeed,
        uint256 votingCycle
    )
        external
        useActor(actorSeed)
    {
        // Bound parameters
        againstThreshold = uint248(bound(againstThreshold, 1, 10000));
        votingCycle = bound(votingCycle, 1, 10);

        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.MaintenanceUpgrade;

        string memory description = string(abi.encodePacked("Maintenance Upgrade #", vm.toString(descriptionSeed)));

        mockEAS.forTest_setAttestation(
            bytes32(hex"1234"),
            Attestation({
                uid: bytes32(hex"1234"),
                schema: validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: address(0),
                attester: validator.owner(),
                revocable: false,
                data: abi.encode(actor, uint8(proposalType))
            })
        );

        // Create optimistic module settings
        IOptimisticModule.ProposalSettings memory settings =
            IOptimisticModule.ProposalSettings({ againstThreshold: againstThreshold, isRelativeToVotableSupply: true });

        bytes memory votingModuleData = abi.encode(settings);
        bytes32 proposalHash = _calculateProposalHash(votingModule, votingModuleData, description);

        vm.prank(actor);
        try validator.submitUpgradeProposal(
            againstThreshold, description, bytes32(hex"1234"), proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            // Store proposal data in scoped block to reduce stack depth
            {
                submittedProposals.push(returnedHash);
                proposalTypes[returnedHash] = proposalType;
                proposalProposers[returnedHash] = actor;
                proposalVotingModuleData[returnedHash] = votingModuleData;
                proposalDescriptions[returnedHash] = description;
                proposalAgainstThresholds[returnedHash] = againstThreshold;
                _updateGhostOnSubmitWithProposer(returnedHash, proposalType, actor);
                _updateGhostProposalVotingCycle(returnedHash, votingCycle);
            }
        } catch (bytes memory reason) {
            // Expected reverts for maintenance proposals
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidUpgradeProposalType()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidAttestation()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidAgainstThreshold()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadySubmitted()"))
            );
        }
    }

    function handler_submitCouncilMemberElectionsProposal(
        uint256 actorSeed,
        uint128 criteriaValue,
        uint256 optionsSeed,
        uint256 descriptionSeed,
        uint256 votingCycle
    )
        external
        useActor(actorSeed)
    {
        ProposalParams memory params = ProposalParams({
            optionsLength: bound(optionsSeed, 2, 5),
            description: string(abi.encodePacked("Council Elections #", vm.toString(descriptionSeed))),
            criteriaValue: uint128(bound(criteriaValue, 1, bound(optionsSeed, 2, 5) - 1)),
            votingCycle: bound(votingCycle, 1, 10),
            proposalType: ProposalValidator.ProposalType.CouncilMemberElections
        });

        mockEAS.forTest_setAttestation(
            bytes32(hex"1234"),
            Attestation({
                uid: bytes32(hex"1234"),
                schema: validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: address(0),
                attester: validator.owner(),
                revocable: false,
                data: abi.encode(actor, uint8(params.proposalType))
            })
        );

        string[] memory optionDescriptions = _buildOptionDescriptions(params.optionsLength, "Candidate ");

        _submitElectionProposal(params, optionDescriptions);
    }

    function handler_submitGovernanceFundProposal(
        uint256 actorSeed,
        uint128 criteriaValue,
        uint256 optionsSeed,
        uint256 descriptionSeed,
        uint256 votingCycle
    )
        external
        useActor(actorSeed)
    {
        ProposalParams memory params = ProposalParams({
            optionsLength: bound(optionsSeed, 1, 3),
            description: string(abi.encodePacked("Governance Fund #", vm.toString(descriptionSeed))),
            criteriaValue: uint128(bound(criteriaValue, 1, 1000 ether)),
            votingCycle: bound(votingCycle, 1, 10),
            proposalType: ProposalValidator.ProposalType.GovernanceFund
        });

        mockEAS.forTest_setAttestation(
            bytes32(hex"1234"),
            Attestation({
                uid: bytes32(hex"1234"),
                schema: validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: address(0),
                attester: validator.owner(),
                revocable: false,
                data: abi.encode(actor, uint8(params.proposalType))
            })
        );

        _submitFundingProposal(params, optionsSeed, "recipient");
    }

    function handler_submitCouncilBudgetProposal(
        uint256 actorSeed,
        uint128 criteriaValue,
        uint256 optionsSeed,
        uint256 descriptionSeed,
        uint256 votingCycle
    )
        external
        useActor(actorSeed)
    {
        ProposalParams memory params = ProposalParams({
            optionsLength: bound(optionsSeed, 1, 3),
            description: string(abi.encodePacked("Council Budget #", vm.toString(descriptionSeed))),
            criteriaValue: uint128(bound(criteriaValue, 1, 1000 ether)),
            votingCycle: bound(votingCycle, 1, 10),
            proposalType: ProposalValidator.ProposalType.CouncilBudget
        });

        mockEAS.forTest_setAttestation(
            bytes32(hex"1234"),
            Attestation({
                uid: bytes32(hex"1234"),
                schema: validator.APPROVED_PROPOSER_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: address(0),
                attester: validator.owner(),
                revocable: false,
                data: abi.encode(actor, uint8(params.proposalType))
            })
        );

        _submitFundingProposal(params, optionsSeed, "budgetRecipient");
    }

    function handler_approveProposal(uint256 actorSeed, uint256 proposalIndexSeed) external useActor(actorSeed) {
        if (submittedProposals.length == 0) {
            return;
        }

        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        _ensureTopDelegateAttestation(actor);

        vm.prank(actor);
        try validator.approveProposal(proposalHash, bytes32(hex"4567")) {
            // Update ghost variables
            _updateGhostOnApprove(proposalHash);
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_ProposalDoesNotExist()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadyApproved()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidAttestation()"))
            );
        }
    }

    // Handler for moving Protocol/Governor upgrade proposals to vote
    function handler_moveToVoteProtocolOrGovernorUpgradeProposal(
        uint256 actorSeed,
        uint256 proposalIndexSeed
    )
        external
        useActor(actorSeed)
    {
        if (submittedProposals.length == 0) return;

        // address actor = _getActor(actorSeed);
        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        // Only handle Protocol/Governor upgrade proposals
        if (proposalTypes[proposalHash] != ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade) {
            return;
        }

        // Only original proposer can move to vote
        if (proposalProposers[proposalHash] != actor) {
            return;
        }

        string memory description = proposalDescriptions[proposalHash];
        uint248 againstThreshold = proposalAgainstThresholds[proposalHash];

        vm.prank(actor);
        try validator.moveToVoteProtocolOrGovernorUpgradeProposal(againstThreshold, description) {
            _updateGhostOnMoveToVote(proposalHash);
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidProposal()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidProposer()"))
                    || selector == bytes4(keccak256("ProposalValidator_InsufficientApprovals()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadyMovedToVote()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalIdMismatch()"))
            );
        }
    }

    function handler_moveToVoteCouncilMemberElectionsProposal(
        uint256 actorSeed,
        uint256 proposalIndexSeed
    )
        external
        useActor(actorSeed)
    {
        if (submittedProposals.length == 0) return;

        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        // Only handle Council Elections proposals
        if (proposalTypes[proposalHash] != ProposalValidator.ProposalType.CouncilMemberElections) {
            return;
        }

        // Only original proposer can move to vote
        if (proposalProposers[proposalHash] != actor) {
            return;
        }

        string memory description = proposalDescriptions[proposalHash];
        uint128 criteriaValue = uint128(proposalCriteriaValues[proposalHash]);
        string[] memory optionDescriptions = proposalOptionDescriptions[proposalHash];

        vm.prank(actor);
        try validator.moveToVoteCouncilMemberElectionsProposal(criteriaValue, optionDescriptions, description) {
            _updateGhostOnMoveToVote(proposalHash);
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidProposal()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidProposer()"))
                    || selector == bytes4(keccak256("ProposalValidator_InsufficientApprovals()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadyMovedToVote()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidVotingCycle()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalIdMismatch()"))
            );
        }
    }

    function handler_moveToVoteFundingProposal(
        uint256 actorSeed,
        uint256 proposalIndexSeed
    )
        external
        useActor(actorSeed)
    {
        if (submittedProposals.length == 0) {
            return;
        }

        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        ProposalValidator.ProposalType proposalType = proposalTypes[proposalHash];
        if (
            proposalType != ProposalValidator.ProposalType.GovernanceFund
                && proposalType != ProposalValidator.ProposalType.CouncilBudget
        ) {
            return;
        }

        if (proposalProposers[proposalHash] != actor) {
            return;
        }

        string memory description = proposalDescriptions[proposalHash];
        uint128 criteriaValue = uint128(proposalCriteriaValues[proposalHash]);
        string[] memory optionDescriptions = proposalOptionDescriptions[proposalHash];
        address[] memory recipients = proposalOptionRecipients[proposalHash];
        uint256[] memory amounts = proposalOptionAmounts[proposalHash];

        vm.prank(actor);
        try validator.moveToVoteFundingProposal(
            criteriaValue, optionDescriptions, recipients, amounts, description, proposalType
        ) {
            // Calculate total amount for ghost variable update
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < amounts.length; i++) {
                totalAmount += amounts[i];
            }

            // Update ghost variables
            _updateGhostOnMoveToVote(proposalHash);
            _updateGhostFundingMovedToVote(proposalHash, totalAmount, ghost_proposalVotingCycle[proposalHash]);
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidFundingProposalType()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidProposal()"))
                    || selector == bytes4(keccak256("ProposalValidator_InsufficientApprovals()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadyMovedToVote()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidVotingCycle()"))
                    || selector == bytes4(keccak256("ProposalValidator_ExceedsDistributionThreshold()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalIdMismatch()"))
            );
        }
    }

    // Helper function to submit election proposals
    function _submitElectionProposal(ProposalParams memory params, string[] memory optionDescriptions) internal {
        IApprovalVotingModule.ProposalOption[] memory options = _buildElectionOptions(optionDescriptions);

        IApprovalVotingModule.ProposalSettings memory settings = IApprovalVotingModule.ProposalSettings({
            maxApprovals: uint8(params.optionsLength),
            criteria: uint8(IApprovalVotingModule.PassingCriteria.TopChoices),
            budgetToken: address(0),
            criteriaValue: params.criteriaValue,
            budgetAmount: 0
        });

        bytes memory votingModuleData = abi.encode(options, settings);
        bytes32 proposalHash = _calculateProposalHash(votingModule, votingModuleData, params.description);

        vm.prank(actor);
        try validator.submitCouncilMemberElectionsProposal(
            params.criteriaValue, optionDescriptions, params.description, bytes32(hex"1234"), params.votingCycle
        ) returns (bytes32 returnedHash) {
            submittedProposals.push(returnedHash);
            proposalTypes[returnedHash] = params.proposalType;
            proposalProposers[returnedHash] = actor;
            proposalVotingModuleData[returnedHash] = votingModuleData;
            proposalDescriptions[returnedHash] = params.description;
            proposalCriteriaValues[returnedHash] = params.criteriaValue;
            proposalOptionDescriptions[returnedHash] = optionDescriptions;
            _updateGhostOnSubmitWithProposer(returnedHash, params.proposalType, actor);
            _updateGhostProposalVotingCycle(returnedHash, params.votingCycle);
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidAttestation()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidOptionsLength()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidCriteriaValue()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadySubmitted()"))
            );
        }
    }

    // Helper function to submit funding proposals - rewritten to avoid stack depth issues
    function _submitFundingProposal(
        ProposalParams memory params,
        uint256 optionsSeed,
        string memory recipientPrefix
    )
        internal
    {
        // Get option descriptions
        string[] memory optionDescriptions = _buildOptionDescriptions(params.optionsLength, "Option ");

        // Get funding arrays
        (address[] memory recipients, uint256[] memory amounts, uint256 totalAmount) =
            _buildFundingArrays(params.optionsLength, optionsSeed, recipientPrefix);

        // Continue with submission
        _submitFundingProposalPart2(params, optionDescriptions, recipients, amounts, totalAmount);
    }

    // Second part of funding proposal submission
    function _submitFundingProposalPart2(
        ProposalParams memory params,
        string[] memory optionDescriptions,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 totalAmount
    )
        internal
    {
        // Build options
        IApprovalVotingModule.ProposalOption[] memory options =
            _buildFundingOptions(optionDescriptions, recipients, amounts);

        // Build settings
        IApprovalVotingModule.ProposalSettings memory settings = IApprovalVotingModule.ProposalSettings({
            maxApprovals: uint8(params.optionsLength),
            criteria: uint8(IApprovalVotingModule.PassingCriteria.Threshold),
            budgetToken: Predeploys.GOVERNANCE_TOKEN,
            criteriaValue: params.criteriaValue,
            budgetAmount: uint128(totalAmount)
        });

        // Continue with final submission
        _submitFundingProposalPart3(params, optionDescriptions, recipients, amounts, totalAmount, options, settings);
    }

    // Third part of funding proposal submission
    function _submitFundingProposalPart3(
        ProposalParams memory params,
        string[] memory optionDescriptions,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 totalAmount,
        IApprovalVotingModule.ProposalOption[] memory options,
        IApprovalVotingModule.ProposalSettings memory settings
    )
        internal
    {
        bytes memory votingModuleData = abi.encode(options, settings);
        bytes32 proposalHash = _calculateProposalHash(votingModule, votingModuleData, params.description);

        // Extract individual values to reduce stack depth
        uint128 criteriaValue = params.criteriaValue;
        string memory description = params.description;
        ProposalValidator.ProposalType proposalType = params.proposalType;
        uint256 votingCycle = params.votingCycle;

        vm.prank(actor);
        try validator.submitFundingProposal(
            criteriaValue, optionDescriptions, recipients, amounts, description, proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            // Store the proposal data
            _storeFundingProposalFinal(
                returnedHash, params, optionDescriptions, recipients, amounts, totalAmount, votingModuleData
            );
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assert(
                selector == bytes4(keccak256("ProposalValidator_InvalidFundingProposalType()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalTypesDataLengthMismatch()"))
                    || selector == bytes4(keccak256("ProposalValidator_InvalidOptionsLength()"))
                    || selector == bytes4(keccak256("ProposalValidator_ProposalAlreadySubmitted()"))
            );
        }
    }

    // Final storage function
    function _storeFundingProposalFinal(
        bytes32 returnedHash,
        ProposalParams memory params,
        string[] memory optionDescriptions,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 totalAmount,
        bytes memory votingModuleData
    )
        internal
    {
        submittedProposals.push(returnedHash);
        proposalTypes[returnedHash] = params.proposalType;
        proposalProposers[returnedHash] = actor;
        proposalVotingModuleData[returnedHash] = votingModuleData;
        proposalDescriptions[returnedHash] = params.description;
        proposalCriteriaValues[returnedHash] = params.criteriaValue;
        proposalOptionDescriptions[returnedHash] = optionDescriptions;
        proposalOptionRecipients[returnedHash] = recipients;
        proposalOptionAmounts[returnedHash] = amounts;
        _updateGhostOnSubmitWithProposer(returnedHash, params.proposalType, actor);
        _updateGhostTokensRequested(totalAmount);
        _updateGhostProposalVotingCycle(returnedHash, params.votingCycle);
    }

    function _getActor(uint256 seed) internal view returns (address) {
        address[] memory actors = new address[](4);
        actors[0] = owner;
        actors[1] = user;
        actors[2] = topDelegate_A;
        actors[3] = topDelegate_B;
        return actors[seed % actors.length];
    }

    struct ProposalParams {
        uint256 optionsLength;
        string description;
        uint128 criteriaValue;
        uint256 votingCycle;
        ProposalValidator.ProposalType proposalType;
    }

    struct FundingParams {
        string[] optionDescriptions;
        address[] recipients;
        uint256[] amounts;
        uint256 totalAmount;
    }

    function _buildOptionDescriptions(
        uint256 length,
        string memory prefix
    )
        internal
        pure
        returns (string[] memory descriptions)
    {
        descriptions = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            descriptions[i] = string(abi.encodePacked(prefix, vm.toString(i + 1)));
        }
    }

    function _buildFundingArrays(
        uint256 length,
        uint256 seed,
        string memory recipientPrefix
    )
        internal
        returns (address[] memory recipients, uint256[] memory amounts, uint256 totalAmount)
    {
        recipients = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked(recipientPrefix, vm.toString(i))));
            amounts[i] = bound(seed + i, 1 ether, DISTRIBUTION_THRESHOLD / length);
            totalAmount += amounts[i];
        }
    }

    function _buildElectionOptions(string[] memory descriptions)
        internal
        pure
        returns (IApprovalVotingModule.ProposalOption[] memory options)
    {
        options = new IApprovalVotingModule.ProposalOption[](descriptions.length);

        for (uint256 i = 0; i < descriptions.length; i++) {
            options[i] = IApprovalVotingModule.ProposalOption({
                budgetTokensSpent: 0,
                targets: new address[](0),
                values: new uint256[](0),
                calldatas: new bytes[](0),
                description: descriptions[i]
            });
        }
    }

    function _buildFundingOptions(
        string[] memory descriptions,
        address[] memory recipients,
        uint256[] memory amounts
    )
        internal
        pure
        returns (IApprovalVotingModule.ProposalOption[] memory options)
    {
        options = new IApprovalVotingModule.ProposalOption[](descriptions.length);

        for (uint256 i = 0; i < descriptions.length; i++) {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);

            targets[0] = Predeploys.GOVERNANCE_TOKEN;
            calldatas[0] = abi.encodeCall(IERC20.transfer, (recipients[i], amounts[i]));

            options[i] = IApprovalVotingModule.ProposalOption({
                budgetTokensSpent: amounts[i],
                targets: targets,
                values: values,
                calldatas: calldatas,
                description: descriptions[i]
            });
        }
    }

    function _calculateProposalHash(
        address module,
        bytes memory votingModuleData,
        string memory description
    )
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(address(governor), module, votingModuleData, keccak256(bytes(description))));
    }

    /// @notice Ensures a top delegate attestation exists for the given address
    function _ensureTopDelegateAttestation(address _delegate) internal {
        bytes32 attestationUid = bytes32(hex"4567");

        // Create top delegate attestation if it doesn't exist
        mockEAS.forTest_setAttestation(
            attestationUid,
            Attestation({
                uid: attestationUid,
                schema: validator.TOP_DELEGATES_ATTESTATION_SCHEMA_UID(),
                time: uint64(block.timestamp),
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: _delegate,
                attester: validator.owner(),
                revocable: false,
                data: abi.encode("top100", false, "2000-01-01")
            })
        );
    }
}
