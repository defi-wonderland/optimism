// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

// Contracts
import { L2CGTBridge } from "src/L2/L2CGTBridge.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title L2CGTBridge_TestInit
/// @notice Reusable test initialization for `L2CGTBridge` tests.
contract L2CGTBridge_TestInit is CommonTest {
    using stdStorage for StdStorage;

    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    L2CGTBridge internal l2CGTBridge;
    address internal l1CGTBridge;
    ICrossDomainMessenger internal messenger;
    ILiquidityController internal mockLiquidityController;

    uint256 internal constant BRIDGE_AMOUNT = 10 ether;
    uint32 internal constant MIN_GAS_LIMIT = 100_000;

    function setUp() public virtual override {
        super.setUp();

        // Mock contracts
        l1CGTBridge = makeAddr("l1CGTBridge");
        messenger = ICrossDomainMessenger(makeAddr("messenger"));
        mockLiquidityController = ILiquidityController(makeAddr("liquidityController"));

        // Deploy L2CGTBridge implementation
        L2CGTBridge impl = new L2CGTBridge(l1CGTBridge, mockLiquidityController);

        // Deploy proxy
        Proxy proxy = new Proxy(alice);

        // Wrap proxy as L2CGTBridge
        l2CGTBridge = L2CGTBridge(address(proxy));

        // Set implementation
        vm.prank(alice);
        proxy.upgradeTo(address(impl));

        // Initialize the bridge
        vm.prank(alice);
        l2CGTBridge.initialize(messenger);

        // Give alice some ETH for bridging
        vm.deal(alice, 1000 ether);
    }
}

/// @title L2CGTBridge_Constructor_Test
/// @notice Tests for the constructor of the `L2CGTBridge` contract.
contract L2CGTBridge_Constructor_Test is L2CGTBridge_TestInit {
    /// @notice Tests that constructor sets the correct immutable values.
    function test_constructor_succeeds() external view {
        assertEq(l2CGTBridge.l1CGTBridge(), l1CGTBridge);
        assertEq(address(l2CGTBridge.liquidityController()), address(mockLiquidityController));
    }
}

/// @title L2CGTBridge_Initialize_Test
/// @notice Tests for the `initialize` function of the `L2CGTBridge` contract.
contract L2CGTBridge_Initialize_Test is L2CGTBridge_TestInit {
    /// @notice Tests that initialization sets the correct values.
    function test_initialize_succeeds() external view {
        assertEq(address(l2CGTBridge.messenger()), address(messenger));
        assertEq(l2CGTBridge.l1CGTBridge(), l1CGTBridge);
        assertEq(address(l2CGTBridge.liquidityController()), address(mockLiquidityController));
    }

    /// @notice Tests that the contract cannot be initialized twice.
    function test_initialize_doubleInit_reverts() external {
        vm.expectRevert();
        vm.prank(alice);
        l2CGTBridge.initialize(messenger);
    }

    /// @notice Tests initialization with new messenger.
    function test_initialize_withDifferentMessenger_succeeds() external {
        // Deploy new bridge for testing
        L2CGTBridge newImpl = new L2CGTBridge(l1CGTBridge, mockLiquidityController);
        Proxy newProxy = new Proxy(alice);
        L2CGTBridge newBridge = L2CGTBridge(address(newProxy));

        vm.prank(alice);
        newProxy.upgradeTo(address(newImpl));

        ICrossDomainMessenger newMessenger = ICrossDomainMessenger(makeAddr("newMessenger"));

        vm.prank(alice);
        newBridge.initialize(newMessenger);

        assertEq(address(newBridge.messenger()), address(newMessenger));
    }
}

/// @title L2CGTBridge_Version_Test
/// @notice Tests for the `version` function of the `L2CGTBridge` contract.
contract L2CGTBridge_Version_Test is L2CGTBridge_TestInit {
    /// @notice Tests that the version is correctly returned.
    function test_version_succeeds() external view {
        assertEq(l2CGTBridge.version(), "1.0.0");
    }
}

/// @title L2CGTBridge_BridgeCGT_Test
/// @notice Tests for the `bridgeCGT` function of the `L2CGTBridge` contract.
contract L2CGTBridge_BridgeCGT_Test is L2CGTBridge_TestInit {
    /// @notice Tests that bridgeCGT succeeds when called properly.
    function test_bridgeCGT_succeeds() external {
        // Mock the mockLiquidityController.burn() call
        vm.mockCall(address(mockLiquidityController), abi.encodeWithSignature("burn()"), "");

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l1CGTBridge),
                abi.encodeWithSelector(L2CGTBridge.finalizeBridgeCGT.selector, alice, bob, BRIDGE_AMOUNT),
                MIN_GAS_LIMIT
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l2CGTBridge));
        emit CGTBridgeInitiated(alice, bob, BRIDGE_AMOUNT);

        // Call bridgeCGT
        vm.prank(alice);
        l2CGTBridge.bridgeCGT{ value: BRIDGE_AMOUNT }(bob, MIN_GAS_LIMIT);
    }

    /// @notice Tests bridgeCGT with different amounts and gas limits.
    function test_bridgeCGT_fuzz(uint256 _amount, uint32 _minGasLimit) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, 100 ether);
        _minGasLimit = uint32(bound(_minGasLimit, 21000, 1000000));

        // Give alice enough ETH
        vm.deal(alice, _amount);

        // Mock the mockLiquidityController.burn() call
        vm.mockCall(address(mockLiquidityController), abi.encodeWithSignature("burn()"), "");

        // Mock the messenger call
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(
                ICrossDomainMessenger.sendMessage.selector,
                address(l1CGTBridge),
                abi.encodeWithSelector(L2CGTBridge.finalizeBridgeCGT.selector, alice, bob, _amount),
                _minGasLimit
            ),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l2CGTBridge));
        emit CGTBridgeInitiated(alice, bob, _amount);

        // Call bridgeCGT
        vm.prank(alice);
        l2CGTBridge.bridgeCGT{ value: _amount }(bob, _minGasLimit);
    }
}

/// @title L2CGTBridge_FinalizeBridgeCGT_Test
/// @notice Tests for the `finalizeBridgeCGT` function of the `L2CGTBridge` contract.
contract L2CGTBridge_FinalizeBridgeCGT_Test is L2CGTBridge_TestInit {
    /// @notice Tests that finalizeBridgeCGT succeeds when called properly.
    function test_finalizeBridgeCGT_succeeds() external {
        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(l1CGTBridge)
        );

        // Mock the mockLiquidityController.mint() call
        vm.mockCall(
            address(mockLiquidityController),
            abi.encodeWithSelector(ILiquidityController.mint.selector, bob, BRIDGE_AMOUNT),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l2CGTBridge));
        emit CGTBridgeFinalized(alice, bob, BRIDGE_AMOUNT);

        // Call finalizeBridgeCGT from the messenger
        vm.prank(address(messenger));
        l2CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when called from wrong messenger.
    function test_finalizeBridgeCGT_whenWrongMessenger_reverts() external {
        vm.expectRevert(L2CGTBridge.OnlyL1CGTBridge.selector);
        vm.prank(makeAddr("wrongMessenger"));
        l2CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests that finalizeBridgeCGT reverts when wrong xDomainMessageSender.
    function test_finalizeBridgeCGT_whenWrongXDomainSender_reverts() external {
        // Mock the messenger to return the wrong xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(makeAddr("wrongSender"))
        );

        vm.expectRevert(L2CGTBridge.OnlyL1CGTBridge.selector);
        vm.prank(address(messenger));
        l2CGTBridge.finalizeBridgeCGT(alice, bob, BRIDGE_AMOUNT);
    }

    /// @notice Tests finalizeBridgeCGT with different amounts.
    function test_finalizeBridgeCGT_fuzz(uint256 _amount) external {
        // Bound the amount to reasonable values
        _amount = bound(_amount, 1, 1000000 ether);

        // Mock the messenger to return the correct xDomainMessageSender
        vm.mockCall(
            address(messenger),
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(l1CGTBridge)
        );

        // Mock the mockLiquidityController.mint() call
        vm.mockCall(
            address(mockLiquidityController),
            abi.encodeWithSelector(ILiquidityController.mint.selector, bob, _amount),
            ""
        );

        // Expect the event to be emitted
        vm.expectEmit(address(l2CGTBridge));
        emit CGTBridgeFinalized(alice, bob, _amount);

        // Call finalizeBridgeCGT from the messenger
        vm.prank(address(messenger));
        l2CGTBridge.finalizeBridgeCGT(alice, bob, _amount);
    }
}
