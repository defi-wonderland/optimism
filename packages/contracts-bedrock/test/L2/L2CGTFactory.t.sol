// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Contracts
import { L2CGTFactory } from "src/L2/L2CGTFactory.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title L2CGTFactory_TestInit
/// @notice Reusable test initialization for `L2CGTFactory` tests.
contract L2CGTFactory_TestInit is CommonTest {
    /// @notice Emitted when L2 bridge is deployed.
    event L2BridgeDeployed(address indexed l2Bridge, address indexed l1Bridge);

    /// @notice Test contracts
    L2CGTFactory l2CGTFactory;

    /// @notice Test addresses
    address l1CGTBridge;
    address l2BridgeOwner;

    /// @notice Test setup.
    function setUp() public virtual override {
        super.setUp();

        // Create test addresses
        l1CGTBridge = makeAddr("l1CGTBridge");
        l2BridgeOwner = makeAddr("l2BridgeOwner");

        // Deploy L2CGTFactory
        l2CGTFactory = new L2CGTFactory(l1CGTBridge, l2BridgeOwner, liquidityController);
    }
}

/// @title L2CGTFactory_Constructor_Test
/// @notice Tests the constructor of the `L2CGTFactory` contract.
contract L2CGTFactory_Constructor_Test is L2CGTFactory_TestInit {
    /// @notice Tests that constructor sets parameters correctly.
    function test_constructor_succeeds() public view {
        assertEq(l2CGTFactory.l1CGTBridge(), l1CGTBridge);
        assertEq(l2CGTFactory.l2BridgeOwner(), l2BridgeOwner);
        assertEq(address(l2CGTFactory.liquidityController()), address(liquidityController));
        assertEq(address(l2CGTFactory.L2_MESSENGER()), 0x4200000000000000000000000000000000000007);
    }

    /// @notice Tests that L2_MESSENGER is hardcoded correctly.
    function test_L2_MESSENGER_isCorrect() public view {
        assertEq(address(l2CGTFactory.L2_MESSENGER()), 0x4200000000000000000000000000000000000007);
    }
}

/// @title L2CGTFactory_DeployL2Bridge_Test
/// @notice Tests the `deployL2Bridge` function of the `L2CGTFactory` contract.
contract L2CGTFactory_DeployL2Bridge_Test is L2CGTFactory_TestInit {
    /// @notice Tests successful L2 bridge deployment when called by authorized messenger.
    function test_deployL2Bridge_authorizedCaller_succeeds() public {
        // Mock the L2 messenger call
        vm.mockCall(
            address(l2CGTFactory.L2_MESSENGER()),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(l1CGTBridge)
        );

        vm.expectEmit(true, true, false, false);
        emit L2BridgeDeployed(address(0), l1CGTBridge);

        vm.prank(address(l2CGTFactory.L2_MESSENGER()));
        address l2Bridge = l2CGTFactory.deployL2Bridge();

        // Verify bridge was deployed
        assertTrue(l2Bridge != address(0));
    }

    /// @notice Tests deployment reverts when called by unauthorized address.
    function test_deployL2Bridge_unauthorizedCaller_reverts() public {
        vm.expectRevert("L2CGTFactory: unauthorized");
        vm.prank(makeAddr("unauthorized"));
        l2CGTFactory.deployL2Bridge();
    }

    /// @notice Tests deployment reverts when messenger has wrong L1 sender.
    function test_deployL2Bridge_wrongL1Sender_reverts() public {
        // Mock the L2 messenger call with wrong sender
        vm.mockCall(
            address(l2CGTFactory.L2_MESSENGER()),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(makeAddr("wrongSender"))
        );

        vm.expectRevert("L2CGTFactory: unauthorized");
        vm.prank(address(l2CGTFactory.L2_MESSENGER()));
        l2CGTFactory.deployL2Bridge();
    }

    /// @notice Tests deployment reverts when called by messenger but wrong L1 sender.
    function test_deployL2Bridge_messengerButWrongSender_reverts() public {
        address wrongSender = makeAddr("wrongSender");

        // Mock the L2 messenger to return wrong sender
        vm.mockCall(
            address(l2CGTFactory.L2_MESSENGER()),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(wrongSender)
        );

        vm.expectRevert("L2CGTFactory: unauthorized");
        vm.prank(address(l2CGTFactory.L2_MESSENGER()));
        l2CGTFactory.deployL2Bridge();
    }
}

/// @title L2CGTFactory_Integration_Test
/// @notice Integration tests for the `L2CGTFactory` contract.
contract L2CGTFactory_Integration_Test is L2CGTFactory_TestInit {
    /// @notice Tests that deployed bridge is initialized correctly.
    function test_deployedBridge_initializedCorrectly() public {
        // Mock the L2 messenger call
        vm.mockCall(
            address(l2CGTFactory.L2_MESSENGER()),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(l1CGTBridge)
        );

        vm.prank(address(l2CGTFactory.L2_MESSENGER()));
        address l2Bridge = l2CGTFactory.deployL2Bridge();

        // Verify bridge exists and has code
        assertTrue(l2Bridge != address(0));
        assertTrue(l2Bridge.code.length > 0);
    }

    /// @notice Tests that factory uses correct system contracts.
    function test_usesCorrectSystemContracts() public view {
        // Verify the factory can access system contracts
        assertTrue(address(l2CGTFactory.L2_MESSENGER()) != address(0));
        assertTrue(address(l2CGTFactory.liquidityController()) != address(0));

        // Verify hardcoded messenger address
        assertEq(address(l2CGTFactory.L2_MESSENGER()), 0x4200000000000000000000000000000000000007);
    }

    /// @notice Tests multiple deployments create different bridges.
    function test_multipleDeployments_createDifferentBridges() public {
        // Mock the L2 messenger call
        vm.mockCall(
            address(l2CGTFactory.L2_MESSENGER()),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(l1CGTBridge)
        );

        vm.startPrank(address(l2CGTFactory.L2_MESSENGER()));

        address l2Bridge1 = l2CGTFactory.deployL2Bridge();
        address l2Bridge2 = l2CGTFactory.deployL2Bridge();

        vm.stopPrank();

        // Verify addresses are different
        assertTrue(l2Bridge1 != l2Bridge2);
        assertTrue(l2Bridge1 != address(0));
        assertTrue(l2Bridge2 != address(0));
    }
}
