// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { IProposalValidator } from "interfaces/governance/IProposalValidator.sol";
import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { ISchemaRegistry, ISchemaResolver } from "src/vendor/eas/ISchemaRegistry.sol";
import { IEAS, AttestationRequest, AttestationRequestData } from "src/vendor/eas/IEAS.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title ProposalValidator_Init_Test
/// @notice Setup and deployment tests for ProposalValidator using createSelectFork
/// @dev PoC based on voting cycle #38: https://gov.optimism.io/t/voting-cycle-roundup-38/9932
/// @dev The distribution limits and thresholds were defined only for testing purposes.
contract ProposalValidator_Init_Test is Test {
    IProposalValidator public proposalValidator;
    ProposalValidator public proposalValidatorImpl;
    IOptimismGovernor public governor;
    
    // Events from IProposalValidator interface
    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        IProposalValidator.ProposalType proposalType
    );
    
    // Cycle #38: May 22th 19:00 GMT to June 11th 19:00 GMT (21 days total) - 2025
    // START_TIMESTAMP is 1 day before voting period starts (end of Week 2)
    uint256 public constant CYCLE_NUMBER = 38;
    uint256 public constant START_TIMESTAMP = 1749060400; // June 4, 2025 19:00 GMT (1 day before voting period starts)
    uint256 public constant VOTING_DURATION = 1 days; // Move-to-vote window (end of Week 2 to start of Week 3)
    uint256 public constant VOTING_CYCLE_DISTRIBUTION_LIMIT = 20_000 ether; // Max 20k OP per voting cycle
    uint256 public constant PROPOSAL_DISTRIBUTION_THRESHOLD = 10_000 ether; // Max 10k OP per proposal
    uint256 public constant PROPOSAL_REQUIRED_APPROVALS = 4; // Approvals needed from top delegates
    uint8 public constant APPROVAL_VOTING_MODULE_ID = 3; // idInConfigurator for ApprovalVotingModule
    uint8 public constant OPTIMISTIC_VOTING_MODULE_ID = 2; // idInConfigurator for OptimisticVotingModule

    /// @notice Indicates whether a test should run with OP Mainnet fork
    function isOpMainnetForkTest() public view returns (bool) {
        // Check if both required environment variables are set (non-default values)
        string memory rpcUrl = vm.envOr("FORK_RPC_URL", string(""));
        uint256 blockNumber = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));
        
        // Both must be set to non-default values
        return bytes(rpcUrl).length > 0 && blockNumber > 0;
    }

    function setUp() public {
        // Skip all tests if required environment variables are not set
        if (!isOpMainnetForkTest()) {
            return;
        }

        // Get environment variables
        string memory rpcUrl = vm.envString("FORK_RPC_URL");
        uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
        
        // Create fork from environment variables
        vm.createSelectFork(rpcUrl, blockNumber);
        
        // Require OP Mainnet chain ID
        require(block.chainid == 10, "Integration tests require OP Mainnet fork (chain ID 10)");
        
        // Deploy ProposalValidator
        _deployProposalValidator();
    }

    function _deployProposalValidator() internal {
        // Declare the governor address on OP Mainnet
        governor = IOptimismGovernor(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10); // address of the governor on OP Mainnet
        
        // Deploy implementation
        proposalValidatorImpl = new ProposalValidator(governor);
        
        // Deploy proxy
        Proxy proxy = new Proxy(address(this));
        proposalValidator = IProposalValidator(address(proxy));

        // Make the test contract the manager of the governor
        // This is only for testing purposes, in production the authorizedProposer feature will be used instead
        vm.prank(governor.manager());
        governor.setManager(address(proxy));
        
        // Register approved proposer schema following ProposalValidator.t.sol pattern
        bytes32 approvedProposerSchemaUid = ISchemaRegistry(Predeploys.SCHEMA_REGISTRY).register(
            "uint8 proposalType,string date", ISchemaResolver(address(0)), true
        );
        bytes32 topDelegatesSchemaUid = 0xcc51e24772be5054d0792c798e1a3dd80be559598f7d5400e11f24e4a6a0e49c; // Already registered in OP Mainnet
        
        // Create proposal types and data
        (
            ProposalValidator.ProposalType[] memory proposalTypes,
            ProposalValidator.ProposalTypeData[] memory proposalTypesData
        ) = _getProposalTypesAndData();
        
        // Initialize the proxy
        IProxy(payable(address(proposalValidator))).upgradeToAndCall(
            address(proposalValidatorImpl),
            abi.encodeCall(
                proposalValidatorImpl.initialize,
                (
                    address(this), // owner
                    CYCLE_NUMBER,
                    START_TIMESTAMP,
                    VOTING_DURATION,
                    VOTING_CYCLE_DISTRIBUTION_LIMIT,
                    PROPOSAL_DISTRIBUTION_THRESHOLD,
                    approvedProposerSchemaUid,
                    topDelegatesSchemaUid,
                    proposalTypes,
                    proposalTypesData
                )
            )
        );
        
        // Set previous voting cycle data (Cycle #37) for delegate attestation validation
        // Previous cycle: May 1-21, 2025 (21 days before current cycle)
        uint256 previousCycleNumber = CYCLE_NUMBER - 1; // Cycle #37
        uint256 previousStartTimestamp = START_TIMESTAMP - 21 days; // 21 days before current cycle
        uint256 previousDuration = 21 days; // Full cycle duration
        uint256 previousDistributionLimit = 20_000 ether; // Same limit
        
        proposalValidator.setVotingCycleData(
            previousCycleNumber,
            previousStartTimestamp,
            previousDuration,
            previousDistributionLimit
        );
    }

    function _getProposalTypesAndData()
        internal
        pure
        returns (ProposalValidator.ProposalType[] memory, ProposalValidator.ProposalTypeData[] memory)
    {
        ProposalValidator.ProposalType[] memory proposalTypes = new ProposalValidator.ProposalType[](5);
        proposalTypes[0] = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        proposalTypes[1] = ProposalValidator.ProposalType.MaintenanceUpgrade;
        proposalTypes[2] = ProposalValidator.ProposalType.CouncilMemberElections;
        proposalTypes[3] = ProposalValidator.ProposalType.GovernanceFund;
        proposalTypes[4] = ProposalValidator.ProposalType.CouncilBudget;

        ProposalValidator.ProposalTypeData[] memory proposalTypesData = new ProposalValidator.ProposalTypeData[](5);
        // ProtocolOrGovernorUpgrade
        proposalTypesData[0] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            idInConfigurator: OPTIMISTIC_VOTING_MODULE_ID
        });
        // MaintenanceUpgrade
        proposalTypesData[1] =
            ProposalValidator.ProposalTypeData({ requiredApprovals: 0, idInConfigurator: OPTIMISTIC_VOTING_MODULE_ID });
        // CouncilMemberElections
        proposalTypesData[2] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            idInConfigurator: APPROVAL_VOTING_MODULE_ID
        });
        // GovernanceFund
        proposalTypesData[3] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            idInConfigurator: APPROVAL_VOTING_MODULE_ID
        });
        // CouncilBudget
        proposalTypesData[4] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            idInConfigurator: APPROVAL_VOTING_MODULE_ID
        });

        return (proposalTypes, proposalTypesData);
    }

    /// @notice Test that ProposalValidator is deployed and initialized correctly
    function test_proposalValidatorDeployment_succeeds() public {
        // Skip if environment variables not set
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        // Verify the contract is deployed
        assertTrue(address(proposalValidator).code.length > 0, "ProposalValidator should have code");
        assertTrue(address(proposalValidatorImpl).code.length > 0, "ProposalValidator implementation should have code");
        
        // Verify initialization
        assertEq(proposalValidator.version(), "1.0.0", "Version should be correct");
        assertEq(proposalValidator.owner(), address(this), "Owner should be test contract");
        assertEq(proposalValidator.proposalDistributionThreshold(), PROPOSAL_DISTRIBUTION_THRESHOLD, "Distribution threshold should be set");
        
        // Verify voting cycle data
        (uint256 startingTimestamp, uint256 duration, uint256 distributionLimit, uint256 movedToVoteTokenCount) = 
            proposalValidator.votingCycles(CYCLE_NUMBER);
        assertEq(startingTimestamp, START_TIMESTAMP, "Starting timestamp should be set");
        assertEq(duration, VOTING_DURATION, "Duration should be set");
        assertEq(distributionLimit, VOTING_CYCLE_DISTRIBUTION_LIMIT, "Distribution limit should be set");
        assertEq(movedToVoteTokenCount, 0, "Moved to vote token count should be 0");
        
        // Verify proposal type data
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(IProposalValidator.ProposalType.ProtocolOrGovernorUpgrade);
        assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS, "Required approvals should be set");
        assertEq(idInConfigurator, OPTIMISTIC_VOTING_MODULE_ID, "ID in configurator should be set");
    }
    function _createDelegateAttestation(IEAS eas, address delegate) internal returns (bytes32) {
        bytes32 topDelegatesSchemaUid = proposalValidator.topDelegatesAttestationSchemaUid();
        
        // Schema: "string rank,bool includePartialDelegatation,string date"
        bytes memory delegateAttestationData = abi.encode(
            "top100", // rank
            false,  // includePartialDelegatation
            "2025-06-04" // date
        );
        
        AttestationRequest memory delegateRequest = AttestationRequest({
            schema: topDelegatesSchemaUid,
            data: AttestationRequestData({
                recipient: delegate,
                expirationTime: uint64(block.timestamp + 365 days),
                revocable: true,
                refUID: bytes32(0),
                data: delegateAttestationData,
                value: 0
            })
        });
        
        // Top delegate attestations must be issued by the specific resolver contract
        address topDelegateIssuer = 0x359F56AE92F4C3074E7466eD7693CC4715217f74;

        vm.prank(topDelegateIssuer);
        return eas.attest(delegateRequest);
    }

    function _createProposerAttestation(IEAS eas, address proposer, IProposalValidator.ProposalType proposalType) internal returns (bytes32) {
        bytes32 approvedProposerSchemaUid = proposalValidator.approvedProposerAttestationSchemaUid();
        bytes memory proposerAttestationData = abi.encode(
            uint8(proposalType),
            "2025-06-04"
        );
        
        AttestationRequest memory proposerRequest = AttestationRequest({
            schema: approvedProposerSchemaUid,
            data: AttestationRequestData({
                recipient: proposer,
                expirationTime: uint64(block.timestamp + 365 days),
                revocable: true,
                refUID: bytes32(0),
                data: proposerAttestationData,
                value: 0
            })
        });
        
        bytes32 proposerAttestationUid = eas.attest(proposerRequest);
        assertTrue(proposerAttestationUid != bytes32(0), "Proposer attestation should be created");
        return proposerAttestationUid;
    }

    function _setupAddressesAndAttestations(string memory prefix) internal returns (address proposer, bytes32[4] memory delegateAttestations) {
        // Create test addresses with prefix to avoid collisions
        proposer = makeAddr(string.concat(prefix, "_proposer"));
        address[] memory delegates = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            delegates[i] = makeAddr(string.concat(prefix, "_delegate", vm.toString(i + 1)));
        }
        
        // Create delegate attestations
        IEAS eas = IEAS(Predeploys.EAS);
        for (uint256 i = 0; i < 4; i++) {
            delegateAttestations[i] = _createDelegateAttestation(eas, delegates[i]);
        }
    }

    function _approveProposal(uint256 proposalId, bytes32[4] memory delegateAttestations, string memory prefix) internal {
        address[] memory delegates = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            delegates[i] = makeAddr(string.concat(prefix, "_delegate", vm.toString(i + 1)));
        }
        
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(delegates[i]);
            proposalValidator.approveProposal(proposalId, delegateAttestations[i]);
        }
    }

}

/// @title ProposalValidator_FundingProposalFullFlow_Test
/// @notice Complete funding proposal flow integration test for both GovernanceFund and CouncilBudget
/// @dev Tests the full proposal lifecycle from submission to move-to-vote
contract ProposalValidator_FundingProposalFullFlow_Test is ProposalValidator_Init_Test {

    /// @notice Complete governance fund proposal flow from submission to approval
    function test_governanceFundProposalFullFlow_succeeds() public {
        // Skip if environment variables not set
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        vm.warp(START_TIMESTAMP - 1);
        
        (address proposer, bytes32[4] memory delegateAttestations) = _setupAddressesAndAttestations("governance_fund");
        uint256 proposalId = _submitFundingProposal(proposer, IProposalValidator.ProposalType.GovernanceFund);
        _approveProposal(proposalId, delegateAttestations, "governance_fund");

        vm.warp(START_TIMESTAMP);
        _moveFundingToVoteAndValidate(proposer, IProposalValidator.ProposalType.GovernanceFund);
    }

    /// @notice Complete council budget proposal flow from submission to approval
    function test_councilBudgetProposalFullFlow_succeeds() public {
        // Skip if environment variables not set
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        vm.warp(START_TIMESTAMP - 1);
        
        (address proposer, bytes32[4] memory delegateAttestations) = _setupAddressesAndAttestations("council_budget");
        uint256 proposalId = _submitFundingProposal(proposer, IProposalValidator.ProposalType.CouncilBudget);
        _approveProposal(proposalId, delegateAttestations, "council_budget");

        vm.warp(START_TIMESTAMP);
        _moveFundingToVoteAndValidate(proposer, IProposalValidator.ProposalType.CouncilBudget);
    }


    function _submitFundingProposal(address proposer, IProposalValidator.ProposalType proposalType) internal returns (uint256) {
        // Prepare funding proposal parameters
        uint128 criteriaValue = 75;
        string[] memory optionsDescriptions = new string[](3);
        address[] memory optionsRecipients = new address[](3);
        uint256[] memory optionsAmounts = new uint256[](3);
        string memory description;
        
        if (proposalType == IProposalValidator.ProposalType.GovernanceFund) {
            optionsDescriptions[0] = "Option 1";
            optionsDescriptions[1] = "Option 2";
            optionsDescriptions[2] = "Option 3";
            
            optionsRecipients[0] = makeAddr("recipient1");
            optionsRecipients[1] = makeAddr("recipient2");
            optionsRecipients[2] = makeAddr("recipient3");
            
            optionsAmounts[0] = 4000 ether;
            optionsAmounts[1] = 3000 ether;
            optionsAmounts[2] = 2500 ether;
            
            description = "Test governance fund proposal";
        } else {
            optionsDescriptions[0] = "Item A";
            optionsDescriptions[1] = "Item B";
            optionsDescriptions[2] = "Item C";
            
            optionsRecipients[0] = makeAddr("recipient1");
            optionsRecipients[1] = makeAddr("recipient2");
            optionsRecipients[2] = makeAddr("recipient3");
            
            optionsAmounts[0] = 2000 ether;
            optionsAmounts[1] = 1500 ether;
            optionsAmounts[2] = 1000 ether;
            
            description = "Test council budget proposal";
        }
        
        // Submit the proposal
        vm.prank(proposer);
        uint256 proposalId = proposalValidator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            proposalType,
            CYCLE_NUMBER
        );
        
        assertTrue(proposalId != 0, "Proposal ID should not be zero (hash-based ID)");
        return proposalId;
    }


    function _moveFundingToVoteAndValidate(address proposer, IProposalValidator.ProposalType proposalType) internal {
        // Prepare move to vote parameters
        uint128 criteriaValue = 75;
        string[] memory optionsDescriptions = new string[](3);
        address[] memory optionsRecipients = new address[](3);
        uint256[] memory optionsAmounts = new uint256[](3);
        string memory description;
        uint256 totalTokensRequested;
        
        if (proposalType == IProposalValidator.ProposalType.GovernanceFund) {
            optionsDescriptions[0] = "Option 1";
            optionsDescriptions[1] = "Option 2";
            optionsDescriptions[2] = "Option 3";
            
            optionsRecipients[0] = makeAddr("recipient1");
            optionsRecipients[1] = makeAddr("recipient2");
            optionsRecipients[2] = makeAddr("recipient3");
            
            optionsAmounts[0] = 4000 ether;
            optionsAmounts[1] = 3000 ether;
            optionsAmounts[2] = 2500 ether;
            
            description = "Test governance fund proposal";
            totalTokensRequested = 9500 ether;
        } else {
            optionsDescriptions[0] = "Item A";
            optionsDescriptions[1] = "Item B";
            optionsDescriptions[2] = "Item C";
            
            optionsRecipients[0] = makeAddr("recipient1");
            optionsRecipients[1] = makeAddr("recipient2");
            optionsRecipients[2] = makeAddr("recipient3");
            
            optionsAmounts[0] = 2000 ether;
            optionsAmounts[1] = 1500 ether;
            optionsAmounts[2] = 1000 ether;
            
            description = "Test council budget proposal";
            totalTokensRequested = 4500 ether;
        }
        
        // Execute move to vote
        vm.prank(proposer);
        uint256 movedProposalId = proposalValidator.moveToVoteFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            proposalType
        );
        
        assertTrue(movedProposalId > 0, "Move to vote should return valid proposal ID");
        (, , , uint256 movedToVoteTokenCount) = proposalValidator.votingCycles(CYCLE_NUMBER);
        assertEq(movedToVoteTokenCount, totalTokensRequested, "Moved to vote token count should be updated");
        
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(proposalType);
        assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS, "Required approvals should match");
        assertEq(idInConfigurator, APPROVAL_VOTING_MODULE_ID, "Should use approval voting module");
        
    }
}

/// @title ProposalValidator_UpgradeProposalFullFlow_Test
/// @notice Complete upgrade proposal flow integration test for both types
/// @dev Tests maintenance upgrades (direct) and protocol upgrades (with approvals)
contract ProposalValidator_UpgradeProposalFullFlow_Test is ProposalValidator_Init_Test {

    /// @notice Protocol upgrade proposal flow requiring approvals and move-to-vote
    function test_protocolUpgradeProposalFullFlow_succeeds() public {
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        vm.warp(START_TIMESTAMP - 1);
        
        (address proposer, bytes32[4] memory delegateAttestations) = _setupAddressesAndAttestations("protocol_upgrade");
        uint256 proposalId = _submitUpgradeProposal(proposer, IProposalValidator.ProposalType.ProtocolOrGovernorUpgrade);
        _approveProposal(proposalId, delegateAttestations, "protocol_upgrade");

        vm.warp(START_TIMESTAMP);
        _moveUpgradeToVoteAndValidate(proposer, proposalId);
    }

    /// @notice Maintenance upgrade proposal flow (direct submission to governor)
    /// @dev Maintenance upgrades bypass the approval process and are sent directly to the governor
    function test_maintenanceUpgradeProposalFullFlow_succeeds() public {
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        vm.warp(START_TIMESTAMP);
        
        address proposer = makeAddr("maintenance_proposer");
        uint256 proposalId = _submitUpgradeProposal(proposer, IProposalValidator.ProposalType.MaintenanceUpgrade);
        
        // Maintenance upgrades are sent directly to the governor on submission
        // No move-to-vote call needed - just validate the proposal was created
        assertTrue(proposalId > 0, "Maintenance upgrade should return valid proposal ID");
        
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(IProposalValidator.ProposalType.MaintenanceUpgrade);
        assertEq(requiredApprovals, 0, "Maintenance upgrades should not require approvals");
        assertEq(idInConfigurator, OPTIMISTIC_VOTING_MODULE_ID, "Maintenance upgrades should use optimistic voting");
    }

    function _submitUpgradeProposal(address proposer, IProposalValidator.ProposalType proposalType) internal returns (uint256) {
        uint248 againstThreshold = 50;
        string memory description;
        if (proposalType == IProposalValidator.ProposalType.ProtocolOrGovernorUpgrade) {
            description = "Test protocol upgrade proposal";
        } else {
            description = "Test maintenance upgrade proposal";
        }
        
        IEAS eas = IEAS(Predeploys.EAS);
        bytes32 attestationUid = _createProposerAttestation(eas, proposer, proposalType);
        
        vm.prank(proposer);
        uint256 proposalId = proposalValidator.submitUpgradeProposal(
            againstThreshold,
            description,
            attestationUid,
            proposalType,
            CYCLE_NUMBER
        );
        
        assertTrue(proposalId != 0, "Upgrade proposal ID should not be zero");
        return proposalId;
    }

    function _moveUpgradeToVoteAndValidate(address proposer, uint256 proposalId) internal {
        uint248 againstThreshold = 50;
        string memory description = "Test protocol upgrade proposal";
        
        vm.prank(proposer);
        uint256 movedProposalId = proposalValidator.moveToVoteProtocolOrGovernorUpgradeProposal(
            againstThreshold,
            description
        );
        
        assertTrue(movedProposalId > 0, "Move to vote should return valid proposal ID");
        
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(IProposalValidator.ProposalType.ProtocolOrGovernorUpgrade);
        
        assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS, "Protocol upgrades should require approvals");
        assertEq(idInConfigurator, OPTIMISTIC_VOTING_MODULE_ID, "Protocol upgrades should use optimistic voting");
    }
}

/// @title ProposalValidator_CouncilMemberElectionsFullFlow_Test
/// @notice Complete council member elections proposal flow integration test
/// @dev Tests the full elections proposal lifecycle from submission to move-to-vote
contract ProposalValidator_CouncilMemberElectionsFullFlow_Test is ProposalValidator_Init_Test {

    /// @notice Complete council member elections proposal flow from submission to approval
    function test_councilMemberElectionsFullFlow_succeeds() public {
        // Skip if environment variables not set
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        vm.warp(START_TIMESTAMP - 1);
        
        (address proposer, bytes32[4] memory delegateAttestations) = _setupAddressesAndAttestations("elections");
        uint256 proposalId = _submitCouncilMemberElectionsProposal(proposer);
        _approveProposal(proposalId, delegateAttestations, "elections");

        vm.warp(START_TIMESTAMP);
        _moveElectionsToVoteAndValidate(proposer, proposalId);
    }


    function _submitCouncilMemberElectionsProposal(address proposer) internal returns (uint256) {
        uint128 criteriaValue = 3;
        
        string[] memory optionDescriptions = new string[](5);
        optionDescriptions[0] = "Option A";
        optionDescriptions[1] = "Option B";
        optionDescriptions[2] = "Option C";
        optionDescriptions[3] = "Option D";
        optionDescriptions[4] = "Option E";
        
        string memory proposalDescription = "Test elections proposal";
        
        // Create proposer attestation using shared helper
        IEAS eas = IEAS(Predeploys.EAS);
        bytes32 attestationUid = _createProposerAttestation(eas, proposer, IProposalValidator.ProposalType.CouncilMemberElections);
        
        // Submit the council member elections proposal
        vm.prank(proposer);
        uint256 proposalId = proposalValidator.submitCouncilMemberElectionsProposal(
            criteriaValue,
            optionDescriptions,
            proposalDescription,
            attestationUid,
            CYCLE_NUMBER
        );
        
        assertTrue(proposalId != 0, "Elections proposal ID should not be zero (hash-based ID)");
        return proposalId;
    }


    function _moveElectionsToVoteAndValidate(address proposer, uint256 proposalId) internal {
        uint128 criteriaValue = 3;
        
        string[] memory optionDescriptions = new string[](5);
        optionDescriptions[0] = "Option A";
        optionDescriptions[1] = "Option B";
        optionDescriptions[2] = "Option C";
        optionDescriptions[3] = "Option D";
        optionDescriptions[4] = "Option E";
        
        string memory proposalDescription = "Test elections proposal";
        
        // Execute move to vote
        vm.prank(proposer);
        uint256 movedProposalId = proposalValidator.moveToVoteCouncilMemberElectionsProposal(
            criteriaValue,
            optionDescriptions,
            proposalDescription
        );
        
        assertTrue(movedProposalId > 0, "Elections move to vote should return valid proposal ID");
        assertEq(movedProposalId, proposalId, "Moved proposal ID should match original");
        
        // Validate proposal type configuration
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(IProposalValidator.ProposalType.CouncilMemberElections);
        assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS, "Elections required approvals should match");
        assertEq(idInConfigurator, APPROVAL_VOTING_MODULE_ID, "Elections should use approval voting module");
    }
}