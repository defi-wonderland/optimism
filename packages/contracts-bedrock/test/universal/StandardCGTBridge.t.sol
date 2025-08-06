// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { StandardCGTBridgeMock } from "test/mocks/StandardCGTBridgeMock.sol";

/// @title StandardCGTBridge_TestInit
/// @notice Reusable test initialization for `StandardCGTBridge` tests.
/// @dev This setup is primarily for tests focusing on internal stateless logic or default states
///      of the `StandardCGTBridge` contract.
contract StandardCGTBridge_TestInit is CommonTest {
    StandardCGTBridgeMock internal standardCGTBridge;
    ICrossDomainMessenger internal messenger;
    StandardCGTBridgeMock internal otherBridge;
    address internal cgtToken;
    address internal from;
    address internal to;

    function setUp() public override {
        super.setUp();

        from = makeAddr("from");
        to = makeAddr("to");

        cgtToken = makeAddr("cgtToken");
        standardCGTBridge = new StandardCGTBridgeMock();
        messenger = ICrossDomainMessenger(makeAddr("messenger"));
        otherBridge = new StandardCGTBridgeMock();

        standardCGTBridge.init(cgtToken, messenger, otherBridge);
    }
}

/// @title StandardCGTBridge_FinalizeBridgeCGT_Test
/// @notice Tests the `finalizeBridgeCGT` function of the `StandardCGTBridge` contract.
contract StandardCGTBridge_FinalizeBridgeCGT_Test is StandardCGTBridge_TestInit {
    /// @notice Tests that function reverts when called from wrong messenger.
    function test_finalizeBridgeCGT_wrongMessenger_reverts() external {
        // Mock the xDomainMessageSender to return the wrong sender
        vm.prank(makeAddr("wrongMessenger"));
        vm.expectRevert(StandardCGTBridge.Unauthorized.selector);
        standardCGTBridge.finalizeBridgeCGT(from, to, 100, "");
    }

    /// @notice Tests that function reverts when xDomainMessageSender is not otherBridge.
    function test_finalizeBridgeCGT_wrongSender_reverts() external {
        // Mock the xDomainMessageSender to return the wrong sender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(messenger.xDomainMessageSender.selector),
            abi.encode(makeAddr("wrongSender"))
        );

        // Call the function and expect it to revert
        vm.prank(address(messenger));
        vm.expectRevert(StandardCGTBridge.Unauthorized.selector);
        standardCGTBridge.finalizeBridgeCGT(from, to, 100, "");
    }

    /// @notice Tests that function succeeds when called correctly.
    function test_finalizeBridgeCGT_succeeds() external {
        // Mock the xDomainMessageSender to return the correct sender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(messenger.xDomainMessageSender.selector),
            abi.encode(address(otherBridge))
        );

        // Call the function and expect it to succeed
        vm.prank(address(messenger));
        standardCGTBridge.finalizeBridgeCGT(from, to, 100, "");
    }
}
