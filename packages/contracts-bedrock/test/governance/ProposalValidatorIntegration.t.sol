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
import { console } from "forge-std/console.sol";

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
            console.log("Skipping OP Mainnet integration tests - Required env vars not set:");
            console.log("- FORK_RPC_URL: OP Mainnet RPC URL");
            console.log("- FORK_BLOCK_NUMBER: Block number to fork from");
            return;
        }

        // Get environment variables
        string memory rpcUrl = vm.envString("FORK_RPC_URL");
        uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
        
        // Create fork from environment variables
        vm.createSelectFork(rpcUrl, blockNumber);
        
        // Require OP Mainnet chain ID
        require(block.chainid == 10, "Integration tests require OP Mainnet fork (chain ID 10)");
        
        console.log("Forked OP Mainnet at block:", blockNumber);
        
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

}

/// @title ProposalValidator_FundingProposalFullFlow_Test
/// @notice Complete funding proposal flow integration test
/// @dev Tests the full proposal lifecycle from submission to move-to-vote
contract ProposalValidator_FundingProposalFullFlow_Test is ProposalValidator_Init_Test {

    /// @notice Complete funding proposal flow from submission to approval
    function test_fundingProposalFullFlow_succeeds() public {
        // Skip if environment variables not set
        if (!isOpMainnetForkTest()) {
            vm.skip(true);
        }
        // Set timestamp to be within the voting window (before cycle starts)
        vm.warp(START_TIMESTAMP - 1);
        console.log("[OK] Timestamp set to voting window:", START_TIMESTAMP - 1);
        
        // Setup addresses and attestations
        (address proposer, bytes32 proposerAttestation, bytes32[4] memory delegateAttestations) = _setupAddressesAndAttestations();
        
        // Submit proposal and get ID
        uint256 proposalId = _submitFundingProposal(proposer);
        
        // Make required approvals from top delegates (4)
        _approveProposal(proposalId, delegateAttestations);

        // Set timestamp to be within the voting window (after cycle starts) which allows to move to vote
        vm.warp(START_TIMESTAMP);
        
        // Move to vote and validate
        _moveToVoteAndValidate(proposer, proposalId);
    }

    function _setupAddressesAndAttestations() internal returns (address proposer, bytes32 proposerAttestation, bytes32[4] memory delegateAttestations) {
        // Create test addresses
        proposer = makeAddr("proposer");
        address[] memory delegates = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            delegates[i] = makeAddr(string.concat("delegate", vm.toString(i + 1)));
        }
        
        console.log("[OK] Setup phase completed - addresses created and funded");
        
        // Create attestations
        IEAS eas = IEAS(Predeploys.EAS);
        
        // Create approved proposer attestation
        proposerAttestation = _createProposerAttestation(eas, proposer);
        
        // Create delegate attestations
        for (uint256 i = 0; i < 4; i++) {
            delegateAttestations[i] = _createDelegateAttestation(eas, delegates[i]);
        }
        
        console.log("[OK] Attestation creation completed - proposer and 4 delegates attested");
    }

    function _createProposerAttestation(IEAS eas, address proposer) internal returns (bytes32) {
        bytes32 approvedProposerSchemaUid = proposalValidator.approvedProposerAttestationSchemaUid();
        bytes memory proposerAttestationData = abi.encode(
            uint8(IProposalValidator.ProposalType.GovernanceFund),
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

    function _submitFundingProposal(address proposer) internal returns (uint256) {
        // Prepare funding proposal parameters
        uint128 criteriaValue = 75;
        string[] memory optionsDescriptions = new string[](3);
        optionsDescriptions[0] = "Infrastructure Development: Build new governance tools";
        optionsDescriptions[1] = "Community Growth: Marketing campaigns and events";
        optionsDescriptions[2] = "Developer Relations: Developer tools and documentation";
        
        address[] memory optionsRecipients = new address[](3);
        optionsRecipients[0] = makeAddr("recipient1");
        optionsRecipients[1] = makeAddr("recipient2");
        optionsRecipients[2] = makeAddr("recipient3");
        
        uint256[] memory optionsAmounts = new uint256[](3);
        optionsAmounts[0] = 4000 ether;
        optionsAmounts[1] = 3000 ether;
        optionsAmounts[2] = 2500 ether;
        
        string memory description = "Q3 2025 Governance Fund Proposal: Comprehensive ecosystem development initiative";
        IProposalValidator.ProposalType proposalType = IProposalValidator.ProposalType.GovernanceFund;
        
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
        
        // Validate proposal submission - hash-based ID should be non-zero
        assertTrue(proposalId != 0, "Proposal ID should not be zero (hash-based ID)");
        console.log("[OK] Proposal submission completed - ID:", proposalId);
        
        return proposalId;
    }

    function _approveProposal(uint256 proposalId, bytes32[4] memory delegateAttestations) internal {
        address delegate1 = makeAddr("delegate1");
        address delegate2 = makeAddr("delegate2");
        address delegate3 = makeAddr("delegate3");
        address delegate4 = makeAddr("delegate4");
        
        vm.prank(delegate1);
        proposalValidator.approveProposal(proposalId, delegateAttestations[0]);
        console.log("[OK] Delegate 1 approved proposal");
        
        vm.prank(delegate2);
        proposalValidator.approveProposal(proposalId, delegateAttestations[1]);
        console.log("[OK] Delegate 2 approved proposal");
        
        vm.prank(delegate3);
        proposalValidator.approveProposal(proposalId, delegateAttestations[2]);
        console.log("[OK] Delegate 3 approved proposal");
        
        vm.prank(delegate4);
        proposalValidator.approveProposal(proposalId, delegateAttestations[3]);
        console.log("[OK] Delegate 4 approved proposal - threshold reached");
    }

    function _moveToVoteAndValidate(address proposer, uint256 proposalId) internal {
        // Prepare move to vote parameters
        uint128 criteriaValue = 75;
        string[] memory optionsDescriptions = new string[](3);
        optionsDescriptions[0] = "Infrastructure Development: Build new governance tools";
        optionsDescriptions[1] = "Community Growth: Marketing campaigns and events";
        optionsDescriptions[2] = "Developer Relations: Developer tools and documentation";
        
        address[] memory optionsRecipients = new address[](3);
        optionsRecipients[0] = makeAddr("recipient1");
        optionsRecipients[1] = makeAddr("recipient2");
        optionsRecipients[2] = makeAddr("recipient3");
        
        uint256[] memory optionsAmounts = new uint256[](3);
        optionsAmounts[0] = 4000 ether;
        optionsAmounts[1] = 3000 ether;
        optionsAmounts[2] = 2500 ether;
        
        string memory description = "Q3 2025 Governance Fund Proposal: Comprehensive ecosystem development initiative";
        IProposalValidator.ProposalType proposalType = IProposalValidator.ProposalType.GovernanceFund;
        
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
        console.log("[OK] Proposal moved to vote - Governor ID:", movedProposalId);
        
        // Final validation
        (, , , uint256 movedToVoteTokenCount) = proposalValidator.votingCycles(CYCLE_NUMBER);
        uint256 totalTokensRequested = 9500 ether; // 4k + 3k + 2.5k OP
        assertEq(movedToVoteTokenCount, totalTokensRequested, "Moved to vote token count should be updated");
        
        (uint256 requiredApprovals, uint8 idInConfigurator) = 
            proposalValidator.proposalTypesData(IProposalValidator.ProposalType.GovernanceFund);
        assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS, "Required approvals should match");
        assertEq(idInConfigurator, APPROVAL_VOTING_MODULE_ID, "Should use approval voting module");
        
        console.log("[SUCCESS] Complete funding proposal flow validation successful!");
        console.log("- Proposal ID:", proposalId);
        console.log("- Governor Proposal ID:", movedProposalId);
        console.log("- Total OP Requested:", totalTokensRequested / 1 ether, "OP");
        console.log("- Voting Cycle:", CYCLE_NUMBER);
        console.log("- Approval Threshold:", criteriaValue, "%");
    }
}