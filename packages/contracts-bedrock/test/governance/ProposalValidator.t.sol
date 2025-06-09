// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IProposalValidator } from "interfaces/governance/IProposalValidator.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IGovernanceToken } from "interfaces/governance/IGovernanceToken.sol";
import { IEAS, AttestationRequest, AttestationRequestData } from "src/vendor/eas/IEAS.sol";
import { ISchemaRegistry, ISchemaResolver } from "src/vendor/eas/ISchemaRegistry.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Contracts
import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Modules
import { ProposalSettings, ProposalOption, PassingCriteria } from "src/governance/ApprovalVotingModule.sol";

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

/// @title ProposalValidatorForTest
/// @notice A test contract that exposes the private _hashProposal function
contract ProposalValidatorForTest is ProposalValidator {
    constructor(
        bytes32 _attestationSchemaUid,
        IOptimismGovernor _governor,
        IGovernanceToken _governanceToken
    )
        ProposalValidator(_attestationSchemaUid, _governor, _governanceToken)
    { }

    function hashProposalWithModule(
        address _module,
        bytes memory _proposalData,
        bytes32 _descriptionHash
    )
        public
        view
        returns (bytes32)
    {
        return _hashProposalWithModule(_module, _proposalData, _descriptionHash);
    }
}

/// @title ProposalValidator_Init
/// @notice Setup contract for ProposalValidator tests
contract ProposalValidator_Init is CommonTest {
    uint256 public constant TOP_DELEGATE_VOTING_POWER = 10000 ether; // 10k OP
    uint256 public constant CYCLE_NUMBER = 1;
    uint256 public constant START_BLOCK = 1000000;
    uint256 public constant DURATION = 100;
    uint256 public constant DISTRIBUTION_LIMIT = 10000 ether;
    uint256 public constant DISTRIBUTION_THRESHOLD = 10000 ether;
    uint256 public constant PROPOSAL_REQUIRED_APPROVALS = 4;
    uint256 public constant MINIMUM_VOTING_POWER = 10000 ether;

    address owner;
    address rando;
    address topDelegate_A;
    address topDelegate_B;
    address topDelegate_C;
    address topDelegate_D;

    ProposalValidatorForTest public validator;
    ProposalValidatorForTest public impl;
    IOptimismGovernor public governor;
    bytes32 public ATTESTATION_SCHEMA_UID;
    bytes32 public proposalHash;

    event ProposalSubmitted(
        bytes32 indexed proposalHash,
        address indexed proposer,
        string description,
        ProposalValidator.ProposalType proposalType
    );
    event ProposalApproved(bytes32 indexed proposalHash, address indexed approver);
    event ProposalMovedToVote(bytes32 indexed proposalHash, address indexed executor);
    event MinimumVotingPowerSet(uint256 newMinimumVotingPower);
    event VotingCycleDataSet(
        uint256 cycleNumber, uint256 startBlock, uint256 duration, uint256 votingCycleDistributionLimit
    );
    event DistributionThresholdSet(uint256 newDistributionThreshold);
    event ProposalTypeDataSet(
        ProposalValidator.ProposalType proposalType, uint256 requiredApprovals, address proposalVotingModule
    );

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Helper function to make a top delegate.
    function _makeTopDelegate(string memory _name) internal returns (address) {
        address delegate = makeAddr(_name);
        deal(address(governanceToken), delegate, TOP_DELEGATE_VOTING_POWER);
        vm.prank(delegate);
        governanceToken.delegate(delegate);
        return delegate;
    }

    /// @notice Helper function to make a (top) delegate approve a proposal.
    function _approveProposal(address _delegate, bytes32 _proposalHash) internal {
        vm.prank(_delegate);
        validator.approveProposal(_proposalHash);
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
        proposalTypesData[0] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });
        proposalTypesData[1] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });
        proposalTypesData[2] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });
        proposalTypesData[3] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });
        proposalTypesData[4] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });

        return (proposalTypes, proposalTypesData);
    }

    /// @notice Initializes the validator
    function _initializeValidator() internal virtual {
        (
            ProposalValidator.ProposalType[] memory proposalTypes,
            ProposalValidator.ProposalTypeData[] memory proposalTypesData
        ) = _getProposalTypesAndData();

        impl = new ProposalValidatorForTest(ATTESTATION_SCHEMA_UID, governor, governanceToken);

        validator = ProposalValidatorForTest(address(new Proxy(owner)));

        vm.prank(owner);
        IProxy(payable(address(validator))).upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                impl.initialize,
                (
                    owner,
                    MINIMUM_VOTING_POWER,
                    CYCLE_NUMBER,
                    START_BLOCK,
                    DURATION,
                    DISTRIBUTION_LIMIT,
                    DISTRIBUTION_THRESHOLD,
                    proposalTypes,
                    proposalTypesData
                )
            )
        );
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

        _initializeValidator();

        topDelegate_A = _makeTopDelegate("topDelegate_A");
        topDelegate_B = _makeTopDelegate("topDelegate_B");
        topDelegate_C = _makeTopDelegate("topDelegate_C");
        topDelegate_D = _makeTopDelegate("topDelegate_D");
    }

    /// @notice Helper to create a valid attestation for a proposal
    function _createAttestation(
        address _delegate,
        ProposalValidator.ProposalType _proposalType
    )
        internal
        returns (bytes32)
    {
        vm.prank(owner);
        return IEAS(Predeploys.EAS).attest(
            AttestationRequest({
                schema: ATTESTATION_SCHEMA_UID,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: false,
                    refUID: bytes32(0),
                    data: abi.encode(_delegate, _proposalType),
                    value: 0
                })
            })
        );
    }

    /// @notice Helper to create a standard proposal setup
    function _createProposalSetup()
        internal
        view
        returns (
            address[] memory targets_,
            uint256[] memory values_,
            bytes[] memory calldatas_,
            string memory description_
        )
    {
        targets_ = new address[](1);
        targets_[0] = address(0);
        values_ = new uint256[](1);
        values_[0] = 0;
        calldatas_ = new bytes[](1);
        calldatas_[0] = bytes("");
        description_ = "Test proposal";
    }
}

/// @title ProposalValidator_ApproveProposal_Test
/// @notice Happy path tests for approveProposal function
contract ProposalValidator_ApproveProposal_Test is ProposalValidator_Init {
    function setUp() public override {
        super.setUp();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createProposalSetup();

        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        uint8 proposalVotingModule = 0;
        bytes32 attestationUid = _createAttestation(topDelegate_A, proposalType);

        /* vm.prank(topDelegate_A); */
        proposalHash = bytes32(0); // TODO: Implement after submitFundingProposal is implemented
    }

    function test_approveProposal_succeeds() public {
        // Expect event to be emitted when approving
        vm.expectEmit(address(validator));
        emit ProposalApproved(proposalHash, topDelegate_A);
        _approveProposal(topDelegate_A, proposalHash);

        // Expect event to be emitted when approving
        vm.expectEmit(address(validator));
        emit ProposalApproved(proposalHash, topDelegate_B);
        _approveProposal(topDelegate_B, proposalHash);

        // Expect event to be emitted when approving
        vm.expectEmit(address(validator));
        emit ProposalApproved(proposalHash, topDelegate_C);
        _approveProposal(topDelegate_C, proposalHash);

        // Expect event to be emitted when approving
        vm.expectEmit(address(validator));
        emit ProposalApproved(proposalHash, topDelegate_D);
        _approveProposal(topDelegate_D, proposalHash);
    }
}

/// @title ProposalValidator_ApproveProposal_TestFail
/// @notice Sad path tests for approveProposal function
contract ProposalValidator_ApproveProposal_TestFail is ProposalValidator_Init {
    function setUp() public override {
        super.setUp();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createProposalSetup();

        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        uint8 proposalVotingModule = 0;
        bytes32 attestationUid = _createAttestation(topDelegate_A, proposalType);

        /* vm.prank(topDelegate_A); */
        proposalHash = bytes32(0); // TODO: Implement after submitFundingProposal is implemented
    }

    function test_approveProposal_insufficientVotingPower_reverts() public {
        vm.expectRevert(IProposalValidator.ProposalValidator_InsufficientVotingPower.selector);
        _approveProposal(rando, proposalHash);
    }

    function test_approveProposal_alreadyApproved_reverts() public {
        _approveProposal(topDelegate_A, proposalHash);

        vm.expectRevert(IProposalValidator.ProposalValidator_ProposalAlreadyApproved.selector);
        _approveProposal(topDelegate_A, proposalHash);
    }
}

/// @title ProposalValidator_MoveToVote_Test
/// @notice Happy path tests for moveToVote function
contract ProposalValidator_MoveToVote_Test is ProposalValidator_Init {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
    ProposalValidator.ProposalType proposalType;
    uint8 proposalVotingModule;

    function setUp() public override {
        super.setUp();

        (targets, values, calldatas, description) = _createProposalSetup();

        proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        proposalVotingModule = 0;
        bytes32 attestationUid = _createAttestation(topDelegate_A, proposalType);

        /* vm.prank(topDelegate_A); */
        proposalHash = bytes32(0); // TODO: Implement after submitFundingProposal is implemented

        _approveProposal(topDelegate_A, proposalHash);
        _approveProposal(topDelegate_B, proposalHash);
        _approveProposal(topDelegate_C, proposalHash);
        _approveProposal(topDelegate_D, proposalHash);
    }

    function test_moveToVote_succeeds() public {
        _mockAndExpect(
            address(governor),
            abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, proposalVotingModule)),
            abi.encode(1)
        );

        // Expect the ProposalMovedToVote event to be emitted
        vm.expectEmit(address(validator));
        emit ProposalMovedToVote(proposalHash, owner);

        vm.prank(owner);
        uint256 governorProposalId = validator.moveToVote(targets, values, calldatas, description);

        assertEq(governorProposalId, 1);
    }
}

/// @title ProposalValidator_MoveToVote_TestFail
/// @notice Sad path tests for moveToVote function
contract ProposalValidator_MoveToVote_TestFail is ProposalValidator_Init {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
    ProposalValidator.ProposalType proposalType;
    uint8 proposalVotingModule;

    function setUp() public override {
        super.setUp();

        (targets, values, calldatas, description) = _createProposalSetup();

        proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        proposalVotingModule = 0;
        bytes32 attestationUid = _createAttestation(topDelegate_A, proposalType);

        /* vm.prank(topDelegate_A); */
        proposalHash = bytes32(0); // TODO: Implement after submitFundingProposal is implemented
    }

    function test_moveToVote_insufficientApprovals_reverts() public {
        // Only approve with 3 delegates (need 4)
        _approveProposal(topDelegate_A, proposalHash);
        _approveProposal(topDelegate_B, proposalHash);
        _approveProposal(topDelegate_C, proposalHash);

        vm.expectRevert(IProposalValidator.ProposalValidator_InsufficientApprovals.selector);
        vm.prank(owner);
        validator.moveToVote(targets, values, calldatas, description);
    }

    function test_moveToVote_alreadyProposed_reverts() public {
        // Approve with all 4 delegates
        _approveProposal(topDelegate_A, proposalHash);
        _approveProposal(topDelegate_B, proposalHash);
        _approveProposal(topDelegate_C, proposalHash);
        _approveProposal(topDelegate_D, proposalHash);

        _mockAndExpect(
            address(governor),
            abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, proposalVotingModule)),
            abi.encode(1)
        );

        vm.prank(owner);
        validator.moveToVote(targets, values, calldatas, description);

        vm.expectRevert(IProposalValidator.ProposalValidator_ProposalAlreadySubmitted.selector);
        vm.prank(owner);
        validator.moveToVote(targets, values, calldatas, description);
    }
}

/// @title ProposalValidator_Getters_Test
/// @notice Tests for getter functions
contract ProposalValidator_Getters_Test is ProposalValidator_Init {
    function test_canSignOff_succeeds() public {
        bool canSignOff = validator.canSignOff(topDelegate_A);
        assertTrue(canSignOff);

        bool cannotSignOff = validator.canSignOff(rando);
        assertFalse(cannotSignOff);
    }
}

/// @title ProposalValidator_Setters_Test
/// @notice Tests for setter functions
contract ProposalValidator_Setters_Test is ProposalValidator_Init {
    function testFuzz_setMinimumVotingPower_succeeds(uint256 newMinimumVotingPower) public {
        // Expect the MinimumVotingPowerSet event to be emitted
        vm.expectEmit(address(validator));
        emit MinimumVotingPowerSet(newMinimumVotingPower);

        vm.prank(owner);
        validator.setMinimumVotingPower(newMinimumVotingPower);

        assertEq(validator.minimumVotingPower(), newMinimumVotingPower);
    }

    function test_setMinimumVotingPower_notOwner_reverts() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        validator.setMinimumVotingPower(10000 ether);
    }

    function testFuzz_setVotingCycleData_succeeds(
        uint256 cycleNumber,
        uint256 startBlock,
        uint256 duration,
        uint256 distributionLimit
    )
        public
    {
        vm.assume(cycleNumber != CYCLE_NUMBER); // Avoid existing cycle

        // Expect the VotingCycleDataSet event to be emitted
        vm.expectEmit(address(validator));
        emit VotingCycleDataSet(cycleNumber, startBlock, duration, distributionLimit);

        vm.prank(owner);
        validator.setVotingCycleData(cycleNumber, startBlock, duration, distributionLimit);

        (uint256 actualStartBlock, uint256 actualDuration, uint256 actualDistributionLimit) =
            validator.votingCycles(cycleNumber);

        assertEq(actualStartBlock, startBlock);
        assertEq(actualDuration, duration);
        assertEq(actualDistributionLimit, distributionLimit);
    }

    function test_setVotingCycleData_notOwner_reverts() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        validator.setVotingCycleData(2, block.number, 100, 10000 ether);
    }

    function test_setVotingCycleData_votingCycleAlreadySet_reverts() public {
        vm.prank(owner);
        validator.setVotingCycleData(2, block.number, 100, 10000 ether);

        vm.expectRevert(ProposalValidator.ProposalValidator_VotingCycleAlreadySet.selector);
        vm.prank(owner);
        validator.setVotingCycleData(2, block.number, 100, 10000 ether);
    }

    function testFuzz_setDistributionThreshold_succeeds(uint256 newDistributionThreshold) public {
        // Expect the DistributionThresholdSet event to be emitted
        vm.expectEmit(address(validator));
        emit DistributionThresholdSet(newDistributionThreshold);

        vm.prank(owner);
        validator.setDistributionThreshold(newDistributionThreshold);

        assertEq(validator.distributionThreshold(), newDistributionThreshold);
    }

    function test_setDistributionThreshold_notOwner_reverts() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        validator.setDistributionThreshold(10000 ether);
    }

    function testFuzz_setProposalTypeData_succeeds(
        uint8 proposalTypeValue,
        uint256 newRequiredApprovals,
        address newConfigurator
    )
        public
    {
        // Bound the proposal type to valid enum values (0-4)
        proposalTypeValue = uint8(bound(proposalTypeValue, 0, 4));
        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType(proposalTypeValue);

        ProposalValidator.ProposalTypeData memory newData = ProposalValidator.ProposalTypeData({
            requiredApprovals: newRequiredApprovals,
            proposalVotingModule: newConfigurator
        });

        // Expect the ProposalTypeDataSet event to be emitted
        vm.expectEmit(address(validator));
        emit ProposalTypeDataSet(proposalType, newRequiredApprovals, newConfigurator);

        vm.prank(owner);
        validator.setProposalTypeData(proposalType, newData);

        (uint256 requiredApprovals, address proposalVotingModule) = validator.proposalTypesData(proposalType);
        assertEq(requiredApprovals, newRequiredApprovals);
        assertEq(proposalVotingModule, newConfigurator);
    }

    function test_setProposalTypeData_notOwner_reverts() public {
        ProposalValidator.ProposalTypeData memory newData =
            ProposalValidator.ProposalTypeData({ requiredApprovals: 4, proposalVotingModule: address(0) });

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        validator.setProposalTypeData(ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade, newData);
    }
}

/// @title ProposalValidator_HashProposalWithModule_Test
/// @notice Tests for the hashProposalWithModule function
contract ProposalValidator_HashProposalWithModule_Test is ProposalValidator_Init {
    function test_hashProposalWithModule_succeeds() public {
        address testModule = makeAddr("testModule");
        bytes memory testProposalData = abi.encode("test", "proposal", "data");
        bytes32 testDescriptionHash = keccak256("test description");

        bytes32 hash = validator.hashProposalWithModule(testModule, testProposalData, testDescriptionHash);
        assertTrue(hash != bytes32(0));
    }

    function test_hashProposalWithModule_consistentHash_succeeds() public {
        address testModule = makeAddr("testModule");
        bytes memory testProposalData = abi.encode("test data");
        bytes32 testDescriptionHash = keccak256("description");

        bytes32 hash1 = validator.hashProposalWithModule(testModule, testProposalData, testDescriptionHash);
        bytes32 hash2 = validator.hashProposalWithModule(testModule, testProposalData, testDescriptionHash);

        assertEq(hash1, hash2);
    }

    function test_hashProposalWithModule_differentInputs_succeeds() public {
        address module1 = makeAddr("module1");
        address module2 = makeAddr("module2");
        bytes memory data = abi.encode("data");
        bytes32 descHash = keccak256("desc");

        bytes32 hash1 = validator.hashProposalWithModule(module1, data, descHash);
        bytes32 hash2 = validator.hashProposalWithModule(module2, data, descHash);

        assertTrue(hash1 != hash2);
    }
}

/// @title ProposalValidator_SubmitFundingProposal_Test
/// @notice Happy path tests for submitFundingProposal function
contract ProposalValidator_SubmitFundingProposal_Test is ProposalValidator_Init {
    address mockApprovalVotingModule;
    uint128 criteriaValue;
    string[] optionsDescriptions;
    address[] optionsRecipients;
    uint256[] optionsAmounts;
    string description;

    event ProposalVotingModuleData(bytes32 indexed proposalHash, bytes encodedVotingModuleData);

    function setUp() public override {
        super.setUp();

        mockApprovalVotingModule = makeAddr("approvalVotingModule");
        
        vm.prank(owner);
        validator.setProposalTypeData(
            ProposalValidator.ProposalType.GovernanceFund,
            ProposalValidator.ProposalTypeData({
                requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
                proposalVotingModule: mockApprovalVotingModule
            })
        );

        vm.prank(owner);
        validator.setProposalTypeData(
            ProposalValidator.ProposalType.CouncilBudget,
            ProposalValidator.ProposalTypeData({
                requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
                proposalVotingModule: mockApprovalVotingModule
            })
        );

        criteriaValue = 1000 ether; // 1000 tokens needed for option to pass
        optionsDescriptions = new string[](2);
        optionsDescriptions[0] = "Option A: Fund development";
        optionsDescriptions[1] = "Option B: Fund marketing";
        
        optionsRecipients = new address[](2);
        optionsRecipients[0] = makeAddr("recipient1");
        optionsRecipients[1] = makeAddr("recipient2");
        
        optionsAmounts = new uint256[](2);
        optionsAmounts[0] = 1000 ether;
        optionsAmounts[1] = 500 ether;
        
        description = "Test funding proposal";
    }

    function test_submitFundingProposal_governanceFund_succeeds() public {
        // Calculate expected proposal hash
        bytes32 expectedHash = validator.hashProposalWithModule(
            mockApprovalVotingModule,
            _constructExpectedVotingModuleData(),
            keccak256(bytes(description))
        );

        // Expect ProposalSubmitted event
        vm.expectEmit(address(validator));
        emit ProposalSubmitted(expectedHash, rando, description, ProposalValidator.ProposalType.GovernanceFund);

        // Expect ProposalVotingModuleData event  
        vm.expectEmit(address(validator));
        emit ProposalVotingModuleData(expectedHash, _constructExpectedVotingModuleData());

        vm.prank(rando);
        bytes32 proposalHash = validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );

        assertEq(proposalHash, expectedHash);
    }

    function _constructExpectedVotingModuleData() internal view returns (bytes memory) {
        // Construct ProposalOption array
        ProposalOption[] memory options = new ProposalOption[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);

            targets[0] = Predeploys.GOVERNANCE_TOKEN;
            calldatas[0] = abi.encodeCall(IERC20.transfer, (optionsRecipients[i], optionsAmounts[i]));

            options[i] = ProposalOption({
                budgetTokensSpent: optionsAmounts[i],
                targets: targets,
                values: values,
                calldatas: calldatas,
                description: optionsDescriptions[i]
            });
        }

        // Construct ProposalSettings
        uint256 totalBudget = optionsAmounts[0] + optionsAmounts[1];
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: uint8(optionsAmounts.length),
            criteria: uint8(PassingCriteria.Threshold),
            budgetToken: Predeploys.GOVERNANCE_TOKEN,
            criteriaValue: criteriaValue,
            budgetAmount: uint128(totalBudget)
        });

        return abi.encode(options, settings);
    }

    function test_submitFundingProposal_councilBudget_succeeds() public {
        // Calculate expected proposal hash
        bytes32 expectedHash = validator.hashProposalWithModule(
            mockApprovalVotingModule,
            _constructExpectedVotingModuleData(),
            keccak256(bytes(description))
        );

        // Expect ProposalSubmitted event
        vm.expectEmit(address(validator));
        emit ProposalSubmitted(expectedHash, rando, description, ProposalValidator.ProposalType.CouncilBudget);

        // Expect ProposalVotingModuleData event  
        vm.expectEmit(address(validator));
        emit ProposalVotingModuleData(expectedHash, _constructExpectedVotingModuleData());

        vm.prank(rando);
        bytes32 proposalHash = validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.CouncilBudget
        );

        assertEq(proposalHash, expectedHash);
    }

    function test_submitFundingProposal_singleOption_succeeds() public {
        string[] memory singleDescription = new string[](1);
        singleDescription[0] = "Single option";
        
        address[] memory singleRecipient = new address[](1);
        singleRecipient[0] = makeAddr("singleRecipient");
        
        uint256[] memory singleAmount = new uint256[](1);
        singleAmount[0] = 100 ether;

        vm.prank(rando);
        bytes32 proposalHash = validator.submitFundingProposal(
            criteriaValue,
            singleDescription,
            singleRecipient,
            singleAmount,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );

        assertTrue(proposalHash != bytes32(0));
    }

    function test_submitFundingProposal_maximumThreshold_succeeds() public {
        // Use amounts at the distribution threshold
        optionsAmounts[0] = DISTRIBUTION_THRESHOLD;
        optionsAmounts[1] = DISTRIBUTION_THRESHOLD;

        vm.prank(rando);
        bytes32 proposalHash = validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );

        assertTrue(proposalHash != bytes32(0));
    }

    function test_submitFundingProposal_zeroAmount_succeeds() public {
        optionsAmounts[0] = 0;
        optionsAmounts[1] = 100 ether;

        vm.prank(rando);
        bytes32 proposalHash = validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );

        assertTrue(proposalHash != bytes32(0));
    }
}

/// @title ProposalValidator_SubmitFundingProposal_TestFail
/// @notice Sad path tests for submitFundingProposal function
contract ProposalValidator_SubmitFundingProposal_TestFail is ProposalValidator_Init {
    address mockApprovalVotingModule;
    uint128 criteriaValue;
    string[] optionsDescriptions;
    address[] optionsRecipients;
    uint256[] optionsAmounts;
    string description;

    function setUp() public override {
        super.setUp();

        mockApprovalVotingModule = makeAddr("approvalVotingModule");
        
        // Set GovernanceFund to use the approval voting module
        vm.prank(owner);
        validator.setProposalTypeData(
            ProposalValidator.ProposalType.GovernanceFund,
            ProposalValidator.ProposalTypeData({
                requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
                proposalVotingModule: mockApprovalVotingModule
            })
        );

        criteriaValue = 50;
        optionsDescriptions = new string[](2);
        optionsDescriptions[0] = "Option A";
        optionsDescriptions[1] = "Option B";
        
        optionsRecipients = new address[](2);
        optionsRecipients[0] = makeAddr("recipient1");
        optionsRecipients[1] = makeAddr("recipient2");
        
        optionsAmounts = new uint256[](2);
        optionsAmounts[0] = 1000 ether;
        optionsAmounts[1] = 500 ether;
        
        description = "Test funding proposal";
    }

    function test_submitFundingProposal_invalidProposalType_reverts() public {
        vm.expectRevert(ProposalValidator.ProposalValidator_InvalidFundingProposalType.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade
        );
    }

    function test_submitFundingProposal_mismatchedDescriptionsLength_reverts() public {
        string[] memory mismatchedDescriptions = new string[](1);
        mismatchedDescriptions[0] = "Only one description";

        vm.expectRevert(ProposalValidator.ProposalValidator_ProposalTypesDataLengthMismatch.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            mismatchedDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function test_submitFundingProposal_mismatchedRecipientsLength_reverts() public {
        address[] memory mismatchedRecipients = new address[](1);
        mismatchedRecipients[0] = makeAddr("onlyOne");

        vm.expectRevert(ProposalValidator.ProposalValidator_ProposalTypesDataLengthMismatch.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            mismatchedRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function test_submitFundingProposal_mismatchedAmountsLength_reverts() public {
        uint256[] memory mismatchedAmounts = new uint256[](1);
        mismatchedAmounts[0] = 100 ether;

        vm.expectRevert(ProposalValidator.ProposalValidator_ProposalTypesDataLengthMismatch.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            mismatchedAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function test_submitFundingProposal_exceedsDistributionThreshold_reverts() public {
        optionsAmounts[0] = DISTRIBUTION_THRESHOLD + 1;

        vm.expectRevert(ProposalValidator.ProposalValidator_ExceedsDistributionThreshold.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function test_submitFundingProposal_duplicateProposal_reverts() public {
        // Submit first proposal
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );

        // Attempt to submit identical proposal
        vm.expectRevert(ProposalValidator.ProposalValidator_ProposalAlreadySubmitted.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function test_submitFundingProposal_multipleAmountsExceedThreshold_reverts() public {
        optionsAmounts[1] = DISTRIBUTION_THRESHOLD + 1;

        vm.expectRevert(ProposalValidator.ProposalValidator_ExceedsDistributionThreshold.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }

    function testFuzz_submitFundingProposal_exceedsDistributionThreshold_reverts(uint256 excessAmount) public {
        vm.assume(excessAmount > DISTRIBUTION_THRESHOLD);
        vm.assume(excessAmount <= type(uint256).max);
        
        optionsAmounts[0] = excessAmount;

        vm.expectRevert(ProposalValidator.ProposalValidator_ExceedsDistributionThreshold.selector);
        vm.prank(rando);
        validator.submitFundingProposal(
            criteriaValue,
            optionsDescriptions,
            optionsRecipients,
            optionsAmounts,
            description,
            ProposalValidator.ProposalType.GovernanceFund
        );
    }
}

/// @title ProposalValidator_Initialize_Test
/// @notice Tests for the initialize function
contract ProposalValidator_Initialize_Test is ProposalValidator_Init {
    /// @dev Override to create validator proxy without initialization for testing
    function _initializeValidator() internal override {
        impl = new ProposalValidatorForTest(ATTESTATION_SCHEMA_UID, governor, governanceToken);
        validator = ProposalValidatorForTest(address(new Proxy(owner)));
        // Initialize will be tested manually
    }

    function test_initialize_succeeds() public {
        (
            ProposalValidator.ProposalType[] memory proposalTypes,
            ProposalValidator.ProposalTypeData[] memory proposalTypesData
        ) = _getProposalTypesAndData();

        vm.prank(owner);
        IProxy(payable(address(validator))).upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                impl.initialize,
                (
                    owner,
                    MINIMUM_VOTING_POWER,
                    CYCLE_NUMBER,
                    START_BLOCK,
                    DURATION,
                    DISTRIBUTION_LIMIT,
                    DISTRIBUTION_THRESHOLD,
                    proposalTypes,
                    proposalTypesData
                )
            )
        );

        // Verify initialization was successful
        assertEq(validator.minimumVotingPower(), MINIMUM_VOTING_POWER);
        assertEq(validator.distributionThreshold(), DISTRIBUTION_THRESHOLD);
        assertEq(validator.owner(), owner);

        // Verify voting cycle data
        (uint256 startBlock, uint256 duration, uint256 distributionLimit) = validator.votingCycles(CYCLE_NUMBER);
        assertEq(startBlock, START_BLOCK);
        assertEq(duration, DURATION);
        assertEq(distributionLimit, DISTRIBUTION_LIMIT);

        // Verify proposal type data
        for (uint256 i = 0; i < proposalTypes.length; i++) {
            (uint256 requiredApprovals, address proposalVotingModule) = validator.proposalTypesData(proposalTypes[i]);
            assertEq(requiredApprovals, PROPOSAL_REQUIRED_APPROVALS);
            assertEq(proposalVotingModule, address(0));
        }
    }

    function test_initialize_mismatchedArrayLengths_reverts() public {
        ProposalValidator.ProposalType[] memory proposalTypes = new ProposalValidator.ProposalType[](3);
        proposalTypes[0] = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        proposalTypes[1] = ProposalValidator.ProposalType.MaintenanceUpgrade;
        proposalTypes[2] = ProposalValidator.ProposalType.CouncilMemberElections;

        // Create mismatched array with different length
        ProposalValidator.ProposalTypeData[] memory proposalTypesData = new ProposalValidator.ProposalTypeData[](2);
        proposalTypesData[0] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });
        proposalTypesData[1] = ProposalValidator.ProposalTypeData({
            requiredApprovals: PROPOSAL_REQUIRED_APPROVALS,
            proposalVotingModule: address(0)
        });

        vm.prank(owner);
        vm.expectRevert("Proxy: delegatecall to new implementation contract failed");
        IProxy(payable(address(validator))).upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                impl.initialize,
                (
                    owner,
                    MINIMUM_VOTING_POWER,
                    CYCLE_NUMBER,
                    START_BLOCK,
                    DURATION,
                    DISTRIBUTION_LIMIT,
                    DISTRIBUTION_THRESHOLD,
                    proposalTypes,
                    proposalTypesData
                )
            )
        );
    }
}
