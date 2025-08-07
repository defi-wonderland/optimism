// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { EOA } from "src/libraries/EOA.sol";

/// @title StandardCGTBridgeTester
/// @notice Simple wrapper around the StandardCGTBridge contract that exposes
///         internal functions and provides concrete implementations for virtual functions
///         so they can be more easily tested directly.
contract StandardCGTBridgeTester is StandardCGTBridge {
    /// @notice Initialize the contract for testing
    function init(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge
    )
        external
        initializer
    {
        __StandardCGTBridge_init(_cgtToken, _messenger, _otherBridge);
    }

    /// @notice Expose bridgeCGT function for testing
    function bridgeCGT(
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        override
        onlyEOA
    {
        // Empty implementation for testing modifiers only
        // Actual implementation will be in L1/L2 specific contracts
    }

    /// @notice Expose bridgeCGTTo function for testing
    function bridgeCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        override
        onlyEOA
    {
        // Empty implementation for testing modifiers only
        // Actual implementation will be in L1/L2 specific contracts
    }

    /// @notice Expose finalizeBridgeCGT function for testing
    function finalizeBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        override
        onlyOtherBridge
    {
        // Empty implementation for testing modifiers only
        // Actual implementation will be in L1/L2 specific contracts
    }
}

/// @title StandardCGTBridge_TestInit
/// @notice Reusable test initialization for `StandardCGTBridge` tests.
/// @dev This setup is primarily for tests focusing on internal stateless logic or default states
///      of the `StandardCGTBridge` contract.
contract StandardCGTBridge_TestInit is CommonTest {
    StandardCGTBridgeTester internal standardCGTBridge;
    ICrossDomainMessenger internal messenger;
    StandardCGTBridgeTester internal otherBridge;
    address internal cgtToken;
    address internal from;
    address internal to;

    function setUp() public override {
        super.setUp();

        from = makeAddr("from");
        to = makeAddr("to");

        cgtToken = makeAddr("cgtToken");
        standardCGTBridge = new StandardCGTBridgeTester();
        messenger = ICrossDomainMessenger(makeAddr("messenger"));
        otherBridge = new StandardCGTBridgeTester();

        standardCGTBridge.init(cgtToken, messenger, otherBridge);
    }
}

/// @title StandardCGTBridge_Initialize_Test
/// @notice Tests the `__StandardCGTBridge_init` function of the `StandardCGTBridge` contract.
contract StandardCGTBridge_Initialize_Test is StandardCGTBridge_TestInit {
    /// @notice Tests that initialization sets the correct values.
    function test_init_succeeds() external view {
        assertEq(standardCGTBridge.cgtToken(), cgtToken);
        assertEq(address(standardCGTBridge.messenger()), address(messenger));
        assertEq(address(standardCGTBridge.otherBridge()), address(otherBridge));
    }

    /// @notice Tests that the contract cannot be initialized twice.
    function test_init_revertsOnDoubleInit() external {
        vm.expectRevert();
        standardCGTBridge.init(address(0x456), messenger, otherBridge);
    }
}

/// @title StandardCGTBridge_OnlyEOA_Test
/// @notice Tests the `onlyEOA` modifier of the `StandardCGTBridge` contract.
contract StandardCGTBridge_OnlyEOA_Test is StandardCGTBridge_TestInit {
    /// @notice Tests that EOA can call functions with onlyEOA modifier.
    function test_bridgeCGT_onlyEOA_fromEOA_succeeds() external {
        // Call the function and expect it to succeed
        // Use startPrank with tx.origin to simulate a proper EOA transaction
        vm.startPrank(from, from);
        standardCGTBridge.bridgeCGT(100, 100, "");
        vm.stopPrank();
    }

    /// @notice Tests that contract cannot call functions with onlyEOA modifier.
    function test_bridgeCGT_onlyEOA_fromContract_reverts() external {
        // Expect the function to revert
        vm.expectRevert(StandardCGTBridge.FunctionCanOnlyBeCalledFromEOA.selector);
        vm.prank(address(otherBridge));
        standardCGTBridge.bridgeCGT(100, 100, "");
    }

    /// @notice Tests that EOA can call functions with onlyEOA modifier.
    function test_bridgeCGTTo_onlyEOA_fromEOA_succeeds() external {
        // Call the function and expect it to succeed
        // Use startPrank with tx.origin to simulate a proper EOA transaction
        vm.startPrank(from, from);
        standardCGTBridge.bridgeCGTTo(to, 100, 100, "");
        vm.stopPrank();
    }

    /// @notice Tests that contract cannot call functions with onlyEOA modifier.
    function test_bridgeCGTTo_onlyEOA_fromContract_reverts() external {
        // Expect the function to revert
        vm.expectRevert(StandardCGTBridge.FunctionCanOnlyBeCalledFromEOA.selector);
        vm.prank(address(otherBridge));
        standardCGTBridge.bridgeCGTTo(to, 100, 100, "");
    }
}

/// @title StandardCGTBridge_OnlyOtherBridge_Test
/// @notice Tests the `onlyOtherBridge` modifier of the `StandardCGTBridge` contract.
contract StandardCGTBridge_OnlyOtherBridge_Test is StandardCGTBridge_TestInit {
    /// @notice Tests that function reverts when called from wrong messenger.
    function test_finalizeBridgeCGT_onlyOtherBridge_wrongMessenger_reverts() external {
        // Mock the xDomainMessageSender to return the wrong sender
        vm.prank(makeAddr("wrongMessenger"));
        vm.expectRevert(StandardCGTBridge.FunctionCanOnlyBeCalledFromOtherBridge.selector);
        standardCGTBridge.finalizeBridgeCGT(from, to, 100, "");
    }

    /// @notice Tests that function reverts when xDomainMessageSender is not otherBridge.
    function test_finalizeBridgeCGT_onlyOtherBridge_wrongXDomainSender_reverts() external {
        // Mock the xDomainMessageSender to return the wrong sender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(messenger.xDomainMessageSender.selector),
            abi.encode(makeAddr("wrongSender"))
        );

        // Call the function and expect it to revert
        vm.prank(address(messenger));
        vm.expectRevert(StandardCGTBridge.FunctionCanOnlyBeCalledFromOtherBridge.selector);
        standardCGTBridge.finalizeBridgeCGT(from, to, 100, "");
    }

    /// @notice Tests that function succeeds when called correctly.
    function test_finalizeBridgeCGT_onlyOtherBridge_correctCaller_succeeds() external {
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
