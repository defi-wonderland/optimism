// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ProposalValidator } from "src/governance/ProposalValidator.sol";
import { IOptimismGovernor } from "interfaces/governance/IOptimismGovernor.sol";
import { IEAS, AttestationRequest, AttestationRequestData } from "src/vendor/eas/IEAS.sol";
import { ISchemaRegistry, ISchemaResolver } from "src/vendor/eas/ISchemaRegistry.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";

contract ProposalValidator_Test is CommonTest {
    uint256 public constant TOP_DELEGATE_VOTING_POWER = 10000 ether; // 10k OP

    address owner;
    address rando;
    address topDelegate_A;
    address topDelegate_B;
    address topDelegate_C;
    address topDelegate_D;

    address public impl;
    ProposalValidator public validatorProxy;
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

    function _approveProposal(address _delegate, bytes32 _proposalHash) internal {
        vm.prank(_delegate);
        validatorProxy.approveProposal(_proposalHash);
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

        impl = address(new ProposalValidator(ATTESTATION_SCHEMA_UID));
        validatorProxy = ProposalValidator(address(new Proxy(owner)));

        vm.prank(owner);
        IProxy(payable(address(validatorProxy))).upgradeToAndCall(address(impl), abi.encodeCall(impl.initialize, (governor, governanceToken, TOP_DELEGATE_VOTING_POWER, owner)));

        topDelegate_A = _makeTopDelegate("topDelegate_A");
        topDelegate_B = _makeTopDelegate("topDelegate_B");
        topDelegate_C = _makeTopDelegate("topDelegate_C");
        topDelegate_D = _makeTopDelegate("topDelegate_D");
    }

    function test_proposalHappyPath_succeeds() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = bytes("");
        string memory description = "Test proposal";
        ProposalValidator.ProposalType proposalType = ProposalValidator.ProposalType.ProtocolOrGovernorUpgrade;
        uint8 proposalTypeConfigurator = 0;

        // Create attestation for the delegate
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

        // Submit the proposal
        vm.prank(topDelegate_A);
        bytes32 proposalHash = validatorProxy.submitProposal(
            targets, values, calldatas, description, proposalType, proposalTypeConfigurator, attestationUid
        );

        // Collect all required approvals
        _approveProposal(topDelegate_A, proposalHash);
        _approveProposal(topDelegate_B, proposalHash);
        _approveProposal(topDelegate_C, proposalHash);
        _approveProposal(topDelegate_D, proposalHash);

        // Mock the governor call
        _mockAndExpect(
            address(governor),
            abi.encodeCall(IOptimismGovernor.propose, (targets, values, calldatas, description, uint8(proposalType))),
            abi.encode(1)
        );

        // Move to vote phase
        vm.prank(owner);
        uint256 governorProposalId = validatorProxy.moveToVote(targets, values, calldatas, description);

        // Verify the proposal was created in the governor
        assertEq(governorProposalId, 1);
    }
}
