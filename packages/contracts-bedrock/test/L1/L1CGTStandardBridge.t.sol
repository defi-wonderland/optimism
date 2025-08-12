// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Contracts
import { L1CGTStandardBridge } from "src/L1/L1CGTStandardBridge.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @title L1CGTStandardBridge_TestInit
/// @notice Reusable test initialization for `L1CGTStandardBridge` tests.
contract L1CGTStandardBridge_TestInit is CommonTest {
    using SafeERC20 for IERC20;

    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    L1CGTStandardBridge internal l1CGTStandardBridge;
    L1CGTStandardBridge internal l2CGTStandardBridge;
    ICrossDomainMessenger internal messenger;
    IOptimismPortal2 internal optimismPortal;
    TestERC20 internal cgtToken;

    uint256 internal constant INITIAL_BALANCE = 1000 ether;
    uint256 internal constant BRIDGE_AMOUNT = 10 ether;
    uint32 internal constant MIN_GAS_LIMIT = 100_000;

    function setUp() public virtual override {
        super.setUp();

        // Deploy mock contracts
        cgtToken = new TestERC20();
        l1CGTStandardBridge = L1CGTStandardBridge(makeAddr("l1CGTStandardBridge"));
        l2CGTStandardBridge = L1CGTStandardBridge(makeAddr("l2CGTStandardBridge"));
        messenger = ICrossDomainMessenger(makeAddr("messenger"));
        optimismPortal = IOptimismPortal2(payable(makeAddr("optimismPortal2")));

        // Deploy L1CGTStandardBridge implementation
        L1CGTStandardBridge impl = new L1CGTStandardBridge();

        // Deploy proxy
        Proxy proxy = new Proxy(alice);

        // Wrap proxy as L1CGTStandardBridge
        l1CGTStandardBridge = L1CGTStandardBridge(address(proxy));

        // Set implementation
        vm.prank(alice);
        proxy.upgradeTo(address(impl));

        // Mock superchainConfig.paused() to return false by default
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(false));

        // Initialize the bridge
        vm.prank(alice);
        l1CGTStandardBridge.initialize(
            address(cgtToken), messenger, l2CGTStandardBridge, systemConfig, superchainConfig, optimismPortal
        );

        // Give alice some CGT tokens
        cgtToken.mint(alice, INITIAL_BALANCE);
    }
}

/// @title L1CGTStandardBridge_Initialize_Test
/// @notice Tests for the `initialize` function of the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_Initialize_Test is L1CGTStandardBridge_TestInit {
    /// @notice Tests that initialization sets the correct values.
    function test_initialize_succeeds() external view {
        assertEq(l1CGTStandardBridge.cgtToken(), address(cgtToken));
        assertEq(address(l1CGTStandardBridge.messenger()), address(messenger));
        assertEq(address(l1CGTStandardBridge.otherBridge()), address(l2CGTStandardBridge));
        assertEq(address(l1CGTStandardBridge.systemConfig()), address(systemConfig));
        assertEq(address(l1CGTStandardBridge.superchainConfig()), address(superchainConfig));
        assertEq(address(l1CGTStandardBridge.optimismPortal()), address(optimismPortal));
    }

    /// @notice Tests that the contract cannot be initialized twice.
    function test_initialize_revertsOnDoubleInit() external {
        vm.expectRevert();
        vm.prank(alice);
        l1CGTStandardBridge.initialize(
            address(cgtToken), messenger, l2CGTStandardBridge, systemConfig, superchainConfig, optimismPortal
        );
    }

    /// @notice Tests that only ProxyAdmin or its owner can initialize.
    function test_initialize_revertsWhenNotProxyAdminOrOwner() external {
        // Deploy new bridge for testing
        L1CGTStandardBridge newImpl = new L1CGTStandardBridge();
        Proxy newProxy = new Proxy(alice);
        L1CGTStandardBridge newBridge = L1CGTStandardBridge(address(newProxy));

        vm.prank(alice);
        newProxy.upgradeTo(address(newImpl));

        // Try to initialize from unauthorized account
        vm.expectRevert();
        vm.prank(bob);
        newBridge.initialize(
            address(cgtToken), messenger, l2CGTStandardBridge, systemConfig, superchainConfig, optimismPortal
        );
    }
}

/// @title L1CGTStandardBridge_Version_Test
/// @notice Tests for the `version` function of the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_Version_Test is L1CGTStandardBridge_TestInit {
    /// @notice Tests that the version is correctly returned.
    function test_version_succeeds() external view {
        assertEq(l1CGTStandardBridge.version(), "1.0.0");
    }
}

/// @title L1CGTStandardBridge_Paused_Test
/// @notice Tests for the `paused` function of the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_Paused_Test is L1CGTStandardBridge_TestInit {
    /// @notice Tests that paused returns the correct value from SuperchainConfig.
    function test_paused_whenNotPaused_returnsFalse() external view {
        assertFalse(l1CGTStandardBridge.paused());
    }

    /// @notice Tests that paused returns true when SuperchainConfig is paused.
    function test_paused_whenPaused_returnsTrue() external {
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        assertTrue(l1CGTStandardBridge.paused());
    }
}

/// @title L1CGTStandardBridge_BridgeCGT_Test
/// @notice Tests for the `bridgeCGT` function of the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_BridgeCGT_Test is L1CGTStandardBridge_TestInit {
    /// @notice Tests that bridgeCGT succeeds when called properly.
    function test_bridgeCGT_succeedsWithRecipient() external {
        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTStandardBridge), BRIDGE_AMOUNT);

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l2CGTStandardBridge),
                abi.encodeWithSelector(L1CGTStandardBridge.finalizeBridgeCGT.selector, alice, alice, BRIDGE_AMOUNT),
                MIN_GAS_LIMIT
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTStandardBridge));
        emit CGTBridgeInitiated(alice, bob, BRIDGE_AMOUNT);

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(bob, BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();

        // Check that tokens were transferred and deposit recorded
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - BRIDGE_AMOUNT);
        assertEq(cgtToken.balanceOf(address(l1CGTStandardBridge)), BRIDGE_AMOUNT);
        assertEq(l1CGTStandardBridge.cgtDeposits(), BRIDGE_AMOUNT);
    }

    /// @notice Tests that bridgeCGT succeeds when recipient is the zero address.
    function test_bridgeCGT_succeedsWhenRecipientIsZeroAddress() external {
        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTStandardBridge), BRIDGE_AMOUNT);

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l2CGTStandardBridge),
                abi.encodeWithSelector(L1CGTStandardBridge.finalizeBridgeCGT.selector, alice, alice, BRIDGE_AMOUNT),
                MIN_GAS_LIMIT
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTStandardBridge));
        emit CGTBridgeInitiated(alice, alice, BRIDGE_AMOUNT);

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(address(0), BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();

        // Check that tokens were transferred and deposit recorded
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - BRIDGE_AMOUNT);
        assertEq(cgtToken.balanceOf(address(l1CGTStandardBridge)), BRIDGE_AMOUNT);
        assertEq(l1CGTStandardBridge.cgtDeposits(), BRIDGE_AMOUNT);
    }

    /// @notice Tests that bridgeCGT reverts when amount is zero.
    function test_bridgeCGT_revertsWhenAmountIsZero() external {
        vm.expectRevert(L1CGTStandardBridge.InvalidAmount.selector);
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(bob, 0, MIN_GAS_LIMIT);
        vm.stopPrank();
    }

    /// @notice Tests that bridgeCGT reverts when bridge is paused.
    function test_bridgeCGT_revertsWhenPaused() external {
        // Mock paused to return true
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        vm.expectRevert(L1CGTStandardBridge.Paused.selector);
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(bob, BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();
    }
}

/// @title L1CGTStandardBridge_FinalizeBridgeCGT_Test
/// @notice Tests for the `finalizeBridgeCGT` function of the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_FinalizeBridgeCGT_Test is L1CGTStandardBridge_TestInit {
    function setUp() public override {
        super.setUp();

        // First, simulate a deposit to set up the contract state
        vm.prank(alice);
        cgtToken.approve(address(l1CGTStandardBridge), BRIDGE_AMOUNT);

        vm.mockCall(address(messenger), abi.encodeWithSelector(ICrossDomainMessenger.sendMessage.selector), "");

        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(alice, BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();
    }

    /// @notice Tests that finalizeBridgeCGT succeeds when called properly.
    function test_finalizeBridgeCGT_succeeds() external {
        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(address(l2CGTStandardBridge))
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTStandardBridge));
        emit CGTBridgeFinalized(alice, bob, BRIDGE_AMOUNT);

        // Call finalizeBridgeCGT from the messenger
        vm.prank(address(messenger));
        l1CGTStandardBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);

        // Check that tokens were transferred and deposit decreased
        assertEq(cgtToken.balanceOf(bob), BRIDGE_AMOUNT);
        assertEq(cgtToken.balanceOf(address(l1CGTStandardBridge)), 0);
        assertEq(l1CGTStandardBridge.cgtDeposits(), 0);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when called from wrong messenger.
    function test_finalizeBridgeCGT_revertsWhenWrongMessenger() external {
        vm.expectRevert(L1CGTStandardBridge.OnlyOtherBridge.selector);
        vm.prank(makeAddr("wrongMessenger"));
        l1CGTStandardBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when wrong xDomainMessageSender.
    function test_finalizeBridgeCGT_revertsWhenWrongXDomainSender() external {
        // Mock the messenger to return the wrong xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(makeAddr("wrongSender"))
        );

        vm.expectRevert(L1CGTStandardBridge.OnlyOtherBridge.selector);
        vm.prank(address(messenger));
        l1CGTStandardBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when bridge is paused.
    function test_finalizeBridgeCGT_revertsWhenPaused() external {
        // Mock paused to return true
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(address(l2CGTStandardBridge))
        );

        vm.expectRevert(L1CGTStandardBridge.Paused.selector);
        vm.prank(address(messenger));
        l1CGTStandardBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }
}

/// @title L1CGTStandardBridge_Fuzz_Test
/// @notice Fuzz tests for the `L1CGTStandardBridge` contract.
contract L1CGTStandardBridge_Fuzz_Test is L1CGTStandardBridge_TestInit {
    /// @notice Fuzz test for bridgeCGT with valid amounts and recipient.
    function testFuzz_bridgeCGT_succeedsWithRecipient(uint256 _amount, uint32 _minGasLimit) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, INITIAL_BALANCE);
        _minGasLimit = uint32(bound(_minGasLimit, 21000, 1000000));

        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTStandardBridge), _amount);

        // Mock the messenger call
        vm.mockCall(address(messenger), abi.encodeWithSelector(ICrossDomainMessenger.sendMessage.selector), "");

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(alice, _amount, _minGasLimit);
        vm.stopPrank();

        // Check that tokens were transferred and deposit recorded
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - _amount);
        assertEq(cgtToken.balanceOf(address(l1CGTStandardBridge)), _amount);
        assertEq(l1CGTStandardBridge.cgtDeposits(), _amount);
    }

    /// @notice Fuzz test for bridgeCGT with valid amounts and zero address recipient.
    function testFuzz_bridgeCGT_succeedsWhenRecipientIsZeroAddress(uint256 _amount, uint32 _minGasLimit) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, INITIAL_BALANCE);
        _minGasLimit = uint32(bound(_minGasLimit, 21000, 1000000));

        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTStandardBridge), _amount);

        // Mock the messenger call
        vm.mockCall(address(messenger), abi.encodeWithSelector(ICrossDomainMessenger.sendMessage.selector), "");

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTStandardBridge.bridgeCGT(address(0), _amount, _minGasLimit);
        vm.stopPrank();

        // Check that tokens were transferred and deposit recorded
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - _amount);
        assertEq(cgtToken.balanceOf(address(l1CGTStandardBridge)), _amount);
        assertEq(l1CGTStandardBridge.cgtDeposits(), _amount);
    }
}
