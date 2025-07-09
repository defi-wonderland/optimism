// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup } from "../Setup.t.sol";
import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { IApprovalVotingModule } from "interfaces/governance/IApprovalVotingModule.sol";
import { IOptimisticModule } from "interfaces/governance/IOptimisticModule.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract HandlersA is Setup {
    // Stored attestations for reuse
    mapping(address => bytes32) public approvedProposerAttestations;
    mapping(address => bytes32) public topDelegateAttestations;

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

    modifier useActor(uint256 actorIndexSeed) {
        address actor = _getActor(actorIndexSeed);
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    function _getActor(uint256 seed) internal view returns (address) {
        address[] memory actors = new address[](4);
        actors[0] = owner;
        actors[1] = user;
        actors[2] = topDelegate_A;
        actors[3] = topDelegate_B;
        return actors[seed % actors.length];
    }

    // Note: No longer need to mock governor calls since MockGovernor handles them properly

    function _ensureAttestation(address actor, ProposalValidator.ProposalType proposalType) internal {
        if (approvedProposerAttestations[actor] == bytes32(0)) {
            approvedProposerAttestations[actor] = _createApprovedProposerAttestation(actor, proposalType);
        }
    }

    function _ensureTopDelegateAttestation(address actor) internal {
        if (topDelegateAttestations[actor] == bytes32(0)) {
            topDelegateAttestations[actor] = _createTopDelegateAttestation(actor);
        }
    }

    // Helper struct to avoid stack too deep
    struct ProposalParams {
        uint256 optionsLength;
        string description;
        uint128 criteriaValue;
        uint256 votingCycle;
        address actor;
        ProposalValidator.ProposalType proposalType;
    }

    // Helper struct for funding proposals
    struct FundingParams {
        string[] optionDescriptions;
        address[] recipients;
        uint256[] amounts;
        uint256 totalAmount;
    }

    // Helper function to build option descriptions
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

    // Helper function to build funding arrays
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

    // Helper function to build approval module options for elections
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

    // Helper function to build approval module options for funding
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

    // Helper function to create proposal hash
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

    // Handler for Protocol/Governor upgrade proposals
    function handler_submitProtocolOrGovernorUpgradeProposal(
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

        address actor = _getActor(actorSeed);
        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;

        string memory description = string(abi.encodePacked("Protocol Upgrade #", vm.toString(descriptionSeed)));

        // Ensure attestation exists
        _ensureAttestation(actor, proposalType);

        // Create optimistic module settings
        IOptimisticModule.ProposalSettings memory settings =
            IOptimisticModule.ProposalSettings({ againstThreshold: againstThreshold, isRelativeToVotableSupply: true });

        bytes memory votingModuleData = abi.encode(settings);
        bytes32 proposalHash = _calculateProposalHash(optimisticVotingModule, votingModuleData, description);

        try validator.submitUpgradeProposal(
            againstThreshold, description, approvedProposerAttestations[actor], proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            // Store proposal data in scoped block to reduce stack depth
            {
                submittedProposals.push(returnedHash);
                proposalTypes[returnedHash] = proposalType;
                proposalProposers[returnedHash] = actor;
                proposalVotingModuleData[returnedHash] = votingModuleData;
                proposalDescriptions[returnedHash] = description;
                proposalAgainstThresholds[returnedHash] = againstThreshold;
                _updateGhostOnSubmit(returnedHash, proposalType);
            }
        } catch {
            // Proposal submission failed, which is expected in some cases
        }
    }

    // Handler for Maintenance upgrade proposals
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

        address actor = _getActor(actorSeed);
        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.MaintenanceUpgrade;

        string memory description = string(abi.encodePacked("Maintenance Upgrade #", vm.toString(descriptionSeed)));

        // Ensure attestation exists
        _ensureAttestation(actor, proposalType);

        // Create optimistic module settings
        IOptimisticModule.ProposalSettings memory settings =
            IOptimisticModule.ProposalSettings({ againstThreshold: againstThreshold, isRelativeToVotableSupply: true });

        bytes memory votingModuleData = abi.encode(settings);
        bytes32 proposalHash = _calculateProposalHash(optimisticVotingModule, votingModuleData, description);

        try validator.submitUpgradeProposal(
            againstThreshold, description, approvedProposerAttestations[actor], proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            // Store proposal data in scoped block to reduce stack depth
            {
                submittedProposals.push(returnedHash);
                proposalTypes[returnedHash] = proposalType;
                proposalProposers[returnedHash] = actor;
                proposalVotingModuleData[returnedHash] = votingModuleData;
                proposalDescriptions[returnedHash] = description;
                proposalAgainstThresholds[returnedHash] = againstThreshold;
                _updateGhostOnSubmit(returnedHash, proposalType);
            }
        } catch {
            // Proposal submission failed, which is expected in some cases
        }
    }

    // Handler for Council Member Elections proposals
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
            actor: _getActor(actorSeed),
            proposalType: ProposalValidator.ProposalType.CouncilMemberElections
        });

        // Ensure attestation exists
        _ensureAttestation(params.actor, params.proposalType);

        string[] memory optionDescriptions = _buildOptionDescriptions(params.optionsLength, "Candidate ");

        _submitElectionProposal(params, optionDescriptions);
    }

    // Handler for GovernanceFund proposals
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
            actor: _getActor(actorSeed),
            proposalType: ProposalValidator.ProposalType.GovernanceFund
        });

        // Ensure attestation exists
        _ensureAttestation(params.actor, params.proposalType);

        _submitFundingProposal(params, optionsSeed, "recipient");
    }

    // Handler for CouncilBudget proposals
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
            actor: _getActor(actorSeed),
            proposalType: ProposalValidator.ProposalType.CouncilBudget
        });

        // Ensure attestation exists
        _ensureAttestation(params.actor, params.proposalType);

        _submitFundingProposal(params, optionsSeed, "budgetRecipient");
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
        bytes32 proposalHash = _calculateProposalHash(approvalVotingModule, votingModuleData, params.description);

        try validator.submitCouncilMemberElectionsProposal(
            params.criteriaValue,
            optionDescriptions,
            params.description,
            approvedProposerAttestations[params.actor],
            params.votingCycle
        ) returns (bytes32 returnedHash) {
            // Store proposal data in scoped block to reduce stack depth
            {
                submittedProposals.push(returnedHash);
                proposalTypes[returnedHash] = params.proposalType;
                proposalProposers[returnedHash] = params.actor;
                proposalVotingModuleData[returnedHash] = votingModuleData;
                proposalDescriptions[returnedHash] = params.description;
                proposalCriteriaValues[returnedHash] = params.criteriaValue;
                proposalOptionDescriptions[returnedHash] = optionDescriptions;
                _updateGhostOnSubmit(returnedHash, params.proposalType);
            }
        } catch {
            // Proposal submission failed, which is expected in some cases
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

        // Ensure we don't exceed distribution limits
        if (totalAmount > DISTRIBUTION_LIMIT) {
            return;
        }

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
        bytes32 proposalHash = _calculateProposalHash(approvalVotingModule, votingModuleData, params.description);

        // Extract individual values to reduce stack depth
        uint128 criteriaValue = params.criteriaValue;
        string memory description = params.description;
        ProposalValidator.ProposalType proposalType = params.proposalType;
        uint256 votingCycle = params.votingCycle;

        // Make validator call
        try validator.submitFundingProposal(
            criteriaValue, optionDescriptions, recipients, amounts, description, proposalType, votingCycle
        ) returns (bytes32 returnedHash) {
            // Store the proposal data
            _storeFundingProposalFinal(
                returnedHash, params, optionDescriptions, recipients, amounts, totalAmount, votingModuleData
            );
        } catch {
            // Proposal submission failed, which is expected in some cases
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
        proposalProposers[returnedHash] = params.actor;
        proposalVotingModuleData[returnedHash] = votingModuleData;
        proposalDescriptions[returnedHash] = params.description;
        proposalCriteriaValues[returnedHash] = params.criteriaValue;
        proposalOptionDescriptions[returnedHash] = optionDescriptions;
        proposalOptionRecipients[returnedHash] = recipients;
        proposalOptionAmounts[returnedHash] = amounts;
        _updateGhostOnSubmit(returnedHash, params.proposalType);
        _updateGhostTokensRequested(totalAmount);
    }

    // Helper functions to store proposal data (removed to reduce stack depth - functionality inlined)

    // Handler for approving proposals
    function handler_approveProposal(uint256 actorSeed, uint256 proposalIndexSeed) external useActor(actorSeed) {
        if (submittedProposals.length == 0) return;

        address actor = _getActor(actorSeed);
        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        // Ensure top delegate attestation exists
        _ensureTopDelegateAttestation(actor);

        try validator.approveProposal(proposalHash, topDelegateAttestations[actor]) {
            // Update ghost variables
            _updateGhostOnApprove(proposalHash);
        } catch {
            // Approval failed, which is expected in some cases
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

        address actor = _getActor(actorSeed);
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

        try validator.moveToVoteProtocolOrGovernorUpgradeProposal(againstThreshold, description) {
            // Update ghost variables
            _updateGhostOnMoveToVote(proposalHash);
        } catch {
            // Move to vote failed, which is expected in some cases
        }
    }

    // Handler for moving Council Elections proposals to vote
    function handler_moveToVoteCouncilMemberElectionsProposal(
        uint256 actorSeed,
        uint256 proposalIndexSeed
    )
        external
        useActor(actorSeed)
    {
        if (submittedProposals.length == 0) return;

        address actor = _getActor(actorSeed);
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

        try validator.moveToVoteCouncilMemberElectionsProposal(criteriaValue, optionDescriptions, description) {
            // Update ghost variables
            _updateGhostOnMoveToVote(proposalHash);
        } catch {
            // Move to vote failed, which is expected in some cases
        }
    }

    // Handler for moving funding proposals to vote
    function handler_moveToVoteFundingProposal(
        uint256 actorSeed,
        uint256 proposalIndexSeed
    )
        external
        useActor(actorSeed)
    {
        if (submittedProposals.length == 0) return;

        address actor = _getActor(actorSeed);
        uint256 proposalIndex = bound(proposalIndexSeed, 0, submittedProposals.length - 1);
        bytes32 proposalHash = submittedProposals[proposalIndex];

        // Only handle funding proposals
        ProposalValidator.ProposalType proposalType = proposalTypes[proposalHash];
        if (
            proposalType != ProposalValidator.ProposalType.GovernanceFund
                && proposalType != ProposalValidator.ProposalType.CouncilBudget
        ) {
            return;
        }

        // Only original proposer can move to vote
        if (proposalProposers[proposalHash] != actor) {
            return;
        }

        string memory description = proposalDescriptions[proposalHash];
        uint128 criteriaValue = uint128(proposalCriteriaValues[proposalHash]);
        string[] memory optionDescriptions = proposalOptionDescriptions[proposalHash];
        address[] memory recipients = proposalOptionRecipients[proposalHash];
        uint256[] memory amounts = proposalOptionAmounts[proposalHash];

        try validator.moveToVoteFundingProposal(
            criteriaValue, optionDescriptions, recipients, amounts, description, proposalType
        ) {
            // Update ghost variables
            _updateGhostOnMoveToVote(proposalHash);
        } catch {
            // Move to vote failed, which is expected in some cases
        }
    }

    // Helper function to get submitted proposals count
    function getSubmittedProposalsCount() external view returns (uint256) {
        return submittedProposals.length;
    }

    // Helper function to get a specific submitted proposal
    function getSubmittedProposal(uint256 index) external view returns (bytes32) {
        return submittedProposals[index];
    }
}
