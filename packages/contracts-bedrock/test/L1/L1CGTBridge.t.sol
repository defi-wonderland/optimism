// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Contracts
import { L1CGTBridge } from "src/L1/L1CGTBridge.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @title L1CGTBridge_TestInit
/// @notice Reusable test initialization for `L1CGTBridge` tests.
contract L1CGTBridge_TestInit is CommonTest {
    using SafeERC20 for IERC20;

    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    L1CGTBridge internal l1CGTBridge;
    L1CGTBridge internal l2CGTBridge;
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
        l1CGTBridge = L1CGTBridge(makeAddr("l1CGTBridge"));
        l2CGTBridge = L1CGTBridge(makeAddr("l2CGTBridge"));
        messenger = ICrossDomainMessenger(makeAddr("messenger"));
        optimismPortal = IOptimismPortal2(payable(makeAddr("optimismPortal2")));

        // Deploy L1CGTBridge implementation
        L1CGTBridge impl = new L1CGTBridge();

        // Deploy proxy
        Proxy proxy = new Proxy(alice);

        // Wrap proxy as L1CGTBridge
        l1CGTBridge = L1CGTBridge(address(proxy));

        // Set implementation
        vm.prank(alice);
        proxy.upgradeTo(address(impl));

        // Mock superchainConfig.paused() to return false by default
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(false));

        // Initialize the bridge
        vm.prank(alice);
        l1CGTBridge.initialize(
            address(cgtToken), messenger, address(l2CGTBridge), systemConfig, superchainConfig, optimismPortal
        );

        // Give alice some CGT tokens
        cgtToken.mint(alice, INITIAL_BALANCE);
    }
}

/// @title L1CGTBridge_Initialize_Test
/// @notice Tests for the `initialize` function of the `L1CGTBridge` contract.
contract L1CGTBridge_Initialize_Test is L1CGTBridge_TestInit {
    /// @notice Tests that initialization sets the correct values.
    function test_initialize_succeeds() external view {
        assertEq(l1CGTBridge.cgtToken(), address(cgtToken));
        assertEq(address(l1CGTBridge.messenger()), address(messenger));
        assertEq(address(l1CGTBridge.otherBridge()), address(l2CGTBridge));
        assertEq(address(l1CGTBridge.systemConfig()), address(systemConfig));
        assertEq(address(l1CGTBridge.superchainConfig()), address(superchainConfig));
        assertEq(address(l1CGTBridge.optimismPortal()), address(optimismPortal));
    }

    /// @notice Tests that the contract cannot be initialized twice.
    function test_initialize_doubleInit_reverts() external {
        vm.expectRevert();
        vm.prank(alice);
        l1CGTBridge.initialize(
            address(cgtToken), messenger, address(l2CGTBridge), systemConfig, superchainConfig, optimismPortal
        );
    }

    /// @notice Tests that only ProxyAdmin or its owner can initialize.
    function test_initialize_whenNotProxyAdminOrOwner_reverts() external {
        // Deploy new bridge for testing
        L1CGTBridge newImpl = new L1CGTBridge();
        Proxy newProxy = new Proxy(alice);
        L1CGTBridge newBridge = L1CGTBridge(address(newProxy));

        vm.prank(alice);
        newProxy.upgradeTo(address(newImpl));

        // Try to initialize from unauthorized account
        vm.expectRevert();
        vm.prank(bob);
        newBridge.initialize(
            address(cgtToken), messenger, address(l2CGTBridge), systemConfig, superchainConfig, optimismPortal
        );
    }
}

/// @title L1CGTBridge_Version_Test
/// @notice Tests for the `version` function of the `L1CGTBridge` contract.
contract L1CGTBridge_Version_Test is L1CGTBridge_TestInit {
    /// @notice Tests that the version is correctly returned.
    function test_version_succeeds() external view {
        assertEq(l1CGTBridge.version(), "1.0.0");
    }
}

/// @title L1CGTBridge_Paused_Test
/// @notice Tests for the `paused` function of the `L1CGTBridge` contract.
contract L1CGTBridge_Paused_Test is L1CGTBridge_TestInit {
    /// @notice Tests that paused returns the correct value from SuperchainConfig.
    function test_paused_whenNotPaused_succeeds() external view {
        assertFalse(l1CGTBridge.paused());
    }

    /// @notice Tests that paused returns true when SuperchainConfig is paused.
    function test_paused_whenPaused_succeeds() external {
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        assertTrue(l1CGTBridge.paused());
    }
}

/// @title L1CGTBridge_BridgeCGT_Test
/// @notice Tests for the `bridgeCGT` function of the `L1CGTBridge` contract.
contract L1CGTBridge_BridgeCGT_Test is L1CGTBridge_TestInit {
    /// @notice Tests that bridgeCGT succeeds when called properly.
    function test_bridgeCGT_withRecipient_succeeds(uint256 _amount, uint32 _minGasLimit) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, INITIAL_BALANCE);
        _minGasLimit = uint32(bound(_minGasLimit, 21000, 1000000));

        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTBridge), _amount);

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l2CGTBridge),
                abi.encodeWithSelector(L1CGTBridge.finalizeBridgeCGT.selector, alice, alice, _amount),
                _minGasLimit
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTBridge));
        emit CGTBridgeInitiated(alice, bob, _amount);

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTBridge.bridgeCGT(bob, _amount, _minGasLimit);
        vm.stopPrank();

        // Check that tokens were transferred
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - _amount);
        assertEq(cgtToken.balanceOf(address(l1CGTBridge)), _amount);
    }

    /// @notice Tests that bridgeCGT succeeds when recipient is the zero address.
    function test_bridgeCGT_whenRecipientIsZeroAddress_succeeds(uint256 _amount, uint32 _minGasLimit) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, INITIAL_BALANCE);
        _minGasLimit = uint32(bound(_minGasLimit, 21000, 1000000));

        // Approve the bridge to spend tokens
        vm.prank(alice);
        cgtToken.approve(address(l1CGTBridge), _amount);

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l2CGTBridge),
                abi.encodeWithSelector(L1CGTBridge.finalizeBridgeCGT.selector, alice, alice, _amount),
                _minGasLimit
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTBridge));
        emit CGTBridgeInitiated(alice, alice, _amount);

        // Call bridgeCGT
        vm.startPrank(alice, alice);
        l1CGTBridge.bridgeCGT(address(0), _amount, _minGasLimit);
        vm.stopPrank();

        // Check that tokens were transferred
        assertEq(cgtToken.balanceOf(alice), INITIAL_BALANCE - _amount);
        assertEq(cgtToken.balanceOf(address(l1CGTBridge)), _amount);
    }

    /// @notice Tests that bridgeCGT reverts when amount is zero.
    function test_bridgeCGT_whenAmountIsZero_reverts() external {
        vm.expectRevert(L1CGTBridge.InvalidAmount.selector);
        vm.startPrank(alice, alice);
        l1CGTBridge.bridgeCGT(bob, 0, MIN_GAS_LIMIT);
        vm.stopPrank();
    }

    /// @notice Tests that bridgeCGT reverts when bridge is paused.
    function test_bridgeCGT_whenPaused_reverts() external {
        // Mock paused to return true
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        vm.expectRevert(L1CGTBridge.Paused.selector);
        vm.startPrank(alice, alice);
        l1CGTBridge.bridgeCGT(bob, BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();
    }
}

/// @title L1CGTBridge_FinalizeBridgeCGT_Test
/// @notice Tests for the `finalizeBridgeCGT` function of the `L1CGTBridge` contract.
contract L1CGTBridge_FinalizeBridgeCGT_Test is L1CGTBridge_TestInit {
    function setUp() public override {
        super.setUp();

        // First, simulate a deposit to set up the contract state
        vm.prank(alice);
        cgtToken.approve(address(l1CGTBridge), BRIDGE_AMOUNT);

        vm.mockCall(address(messenger), abi.encodeWithSelector(ICrossDomainMessenger.sendMessage.selector), "");

        vm.startPrank(alice, alice);
        l1CGTBridge.bridgeCGT(alice, BRIDGE_AMOUNT, MIN_GAS_LIMIT);
        vm.stopPrank();
    }

    /// @notice Tests that finalizeBridgeCGT succeeds when called properly.
    function test_finalizeBridgeCGT_succeeds() external {
        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(address(l2CGTBridge))
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l1CGTBridge));
        emit CGTBridgeFinalized(alice, bob, BRIDGE_AMOUNT);

        // Call finalizeBridgeCGT from the messenger
        vm.prank(address(messenger));
        l1CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);

        // Check that tokens were transferred
        assertEq(cgtToken.balanceOf(bob), BRIDGE_AMOUNT);
        assertEq(cgtToken.balanceOf(address(l1CGTBridge)), 0);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when called from wrong messenger.
    function test_finalizeBridgeCGT_whenWrongMessenger_reverts() external {
        vm.expectRevert(L1CGTBridge.OnlyOtherBridge.selector);
        vm.prank(makeAddr("wrongMessenger"));
        l1CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when wrong xDomainMessageSender.
    function test_finalizeBridgeCGT_whenWrongXDomainSender_reverts() external {
        // Mock the messenger to return the wrong xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(makeAddr("wrongSender"))
        );

        vm.expectRevert(L1CGTBridge.OnlyOtherBridge.selector);
        vm.prank(address(messenger));
        l1CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when bridge is paused.
    function test_finalizeBridgeCGT_whenPaused_reverts() external {
        // Mock paused to return true
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(address(l2CGTBridge))
        );

        vm.expectRevert(L1CGTBridge.Paused.selector);
        vm.prank(address(messenger));
        l1CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }
}
