// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IERC20 } from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/interfaces/IL2ToL2CrossDomainMessenger.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "@openzeppelin/contracts-v5/proxy/utils/Initializable.sol";
import { IERC165 } from "@openzeppelin/contracts-v5/utils/introspection/IERC165.sol";
import { IBeacon } from "@openzeppelin/contracts-v5/proxy/beacon/IBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts-v5/proxy/beacon/BeaconProxy.sol";

// Target contract
import { SuperchainERC20, ISuperchainERC20Extension } from "src/L2/SuperchainERC20.sol";
import { ISuperchainERC20Errors } from "src/L2/interfaces/ISuperchainERC20.sol";

/// @title SuperchainERC20Test
/// @notice Contract for testing the SuperchainERC20 contract.
contract SuperchainERC20Test is Test {
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant REMOTE_TOKEN = address(0x123);
    string internal constant NAME = "SuperchainERC20";
    string internal constant SYMBOL = "SCE";
    uint8 internal constant DECIMALS = 18;
    address internal constant L2_BRIDGE = Predeploys.L2_STANDARD_BRIDGE;
    address internal constant SUPERCHAIN_ERC20_BRIDGE = Predeploys.SUPERCHAIN_ERC20_BRIDGE;
    address internal constant MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    SuperchainERC20 public superchainERC20Impl;
    SuperchainERC20 public superchainERC20;

    /// @notice Sets up the test suite.
    function setUp() public {
        superchainERC20Impl = new SuperchainERC20();

        // Deploy the OptimismSuperchainERC20Beacon contract
        _deployBeacon();

        superchainERC20 = _deploySuperchainERC20Proxy(REMOTE_TOKEN, NAME, SYMBOL, DECIMALS);
    }

    /// @notice Deploy the OptimismSuperchainERC20Beacon predeploy contract
    function _deployBeacon() internal {
        // Deploy the OptimismSuperchainERC20Beacon implementation
        address _addr = Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON;
        address _impl = Predeploys.predeployToCodeNamespace(_addr);
        vm.etch(_impl, vm.getDeployedCode("OptimismSuperchainERC20Beacon.sol:OptimismSuperchainERC20Beacon"));

        // Deploy the ERC1967Proxy contract at the Predeploy
        bytes memory code = vm.getDeployedCode("universal/Proxy.sol:Proxy");
        vm.etch(_addr, code);
        EIP1967Helper.setAdmin(_addr, Predeploys.PROXY_ADMIN);
        EIP1967Helper.setImplementation(_addr, _impl);

        // Mock implementation address
        vm.mockCall(
            _impl, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(address(superchainERC20Impl))
        );
    }

    /// @notice Helper function to deploy a proxy of the SuperchainERC20 contract.
    function _deploySuperchainERC20Proxy(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        internal
        returns (SuperchainERC20)
    {
        return SuperchainERC20(
            address(
                new BeaconProxy(
                    Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON,
                    abi.encodeCall(SuperchainERC20.initialize, (_remoteToken, _name, _symbol, _decimals))
                )
            )
        );
    }

    /// @notice Helper function to fuzz the bridge address to performs the calls with.
    /// @dev Needed to cover both possible branches of the authorized callers on `mint` and `burn` functions.
    function _getBridge(bool _returnL2StandardBridge) internal pure returns (address bridge) {
        bridge = _returnL2StandardBridge ? L2_BRIDGE : SUPERCHAIN_ERC20_BRIDGE;
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Test that the contract's `initializer` sets the correct values.
    function test_initializer_succeeds() public view {
        assertEq(superchainERC20.name(), NAME);
        assertEq(superchainERC20.symbol(), SYMBOL);
        assertEq(superchainERC20.decimals(), DECIMALS);
        assertEq(superchainERC20.remoteToken(), REMOTE_TOKEN);
    }

    /// @notice Tests the `initialize` function reverts when the contract is already initialized.
    function testFuzz_initializer_reverts(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        public
    {
        // Expect the revert with `InvalidInitialization` selector
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        // Call the `initialize` function again
        superchainERC20.initialize(_remoteToken, _name, _symbol, _decimals);
    }

    /// @notice Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_mint_callerNotBridge_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != L2_BRIDGE);
        vm.assume(_caller != SUPERCHAIN_ERC20_BRIDGE);

        // Expect the revert with `OnlyAuthorizedBridge` selector
        vm.expectRevert(ISuperchainERC20Errors.OnlyAuthorizedBridge.selector);

        // Call the `mint` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.__superchainMint(_to, _amount);
    }

    /// @notice Tests the `mint` function reverts when the amount is zero.
    function testFuzz_mint_zeroAddressTo_reverts(uint256 _amount, bool _returnL2StandardBridge) public {
        // Expect the revert with `ZeroAddress` selector
        vm.expectRevert(ISuperchainERC20Errors.ZeroAddress.selector);

        // Call the `mint` function with the zero address
        address bridge = _getBridge(_returnL2StandardBridge);
        vm.prank(bridge);
        superchainERC20.__superchainMint({ _to: ZERO_ADDRESS, _amount: _amount });
    }

    /// @notice Tests the `mint` succeeds and emits the `Mint` event.
    function testFuzz_mint_succeeds(address _to, uint256 _amount, bool _returnL2StandardBridge) public {
        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Get the total supply and balance of `_to` before the mint to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _toBalanceBefore = superchainERC20.balanceOf(_to);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(address(superchainERC20));
        emit IERC20.Transfer(ZERO_ADDRESS, _to, _amount);

        // Look for the emit of the `Mint` event
        vm.expectEmit(address(superchainERC20));
        emit ISuperchainERC20Extension.Mint(_to, _amount);

        // Call the `mint` function with the bridge caller
        address bridge = _getBridge(_returnL2StandardBridge);
        vm.prank(bridge);
        superchainERC20.__superchainMint(_to, _amount);

        // Check the total supply and balance of `_to` after the mint were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(superchainERC20.balanceOf(_to), _toBalanceBefore + _amount);
    }

    /// @notice Tests the `burn` function reverts when the caller is not the bridge.
    function testFuzz_burn_callerNotBridge_reverts(address _caller, address _from, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != L2_BRIDGE);
        vm.assume(_caller != SUPERCHAIN_ERC20_BRIDGE);

        // Expect the revert with `OnlyAuthorizedBridge` selector
        vm.expectRevert(ISuperchainERC20Errors.OnlyAuthorizedBridge.selector);

        // Call the `burn` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.__superchainBurn(_from, _amount);
    }

    /// @notice Tests the `burn` function reverts when the amount is zero.
    function testFuzz_burn_zeroAddressFrom_reverts(uint256 _amount, bool _returnL2StandardBridge) public {
        // Expect the revert with `ZeroAddress` selector
        vm.expectRevert(ISuperchainERC20Errors.ZeroAddress.selector);

        // Call the `burn` function with the zero address
        address bridge = _getBridge(_returnL2StandardBridge);
        vm.prank(bridge);
        superchainERC20.__superchainBurn({ _from: ZERO_ADDRESS, _amount: _amount });
    }

    /// @notice Tests the `burn` burns the amount and emits the `Burn` event.
    function testFuzz_burn_succeeds(address _from, uint256 _amount, bool _returnL2StandardBridge) public {
        // Ensure `_from` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Mint some tokens to `_from` so then they can be burned
        address bridge = _getBridge(_returnL2StandardBridge);
        vm.prank(bridge);
        superchainERC20.__superchainMint(_from, _amount);

        // Get the total supply and balance of `_from` before the burn to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _fromBalanceBefore = superchainERC20.balanceOf(_from);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(address(superchainERC20));
        emit IERC20.Transfer(_from, ZERO_ADDRESS, _amount);

        // Look for the emit of the `Burn` event
        vm.expectEmit(address(superchainERC20));
        emit ISuperchainERC20Extension.Burn(_from, _amount);

        // Call the `burn` function with the bridge caller
        bridge = _getBridge(_returnL2StandardBridge);
        vm.prank(bridge);
        superchainERC20.__superchainBurn(_from, _amount);

        // Check the total supply and balance of `_from` after the burn were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(superchainERC20.balanceOf(_from), _fromBalanceBefore - _amount);
    }

    /// @notice Tests the `decimals` function always returns the correct value.
    function testFuzz_decimals_succeeds(uint8 _decimals) public {
        SuperchainERC20 _newSuperchainERC20 = _deploySuperchainERC20Proxy(REMOTE_TOKEN, NAME, SYMBOL, _decimals);
        assertEq(_newSuperchainERC20.decimals(), _decimals);
    }

    /// @notice Tests the `REMOTE_TOKEN` function always returns the correct value.
    function testFuzz_remoteToken_succeeds(address _remoteToken) public {
        SuperchainERC20 _newSuperchainERC20 = _deploySuperchainERC20Proxy(_remoteToken, NAME, SYMBOL, DECIMALS);
        assertEq(_newSuperchainERC20.remoteToken(), _remoteToken);
    }

    /// @notice Tests the `name` function always returns the correct value.
    function testFuzz_name_succeeds(string memory _name) public {
        SuperchainERC20 _newSuperchainERC20 = _deploySuperchainERC20Proxy(REMOTE_TOKEN, _name, SYMBOL, DECIMALS);
        assertEq(_newSuperchainERC20.name(), _name);
    }

    /// @notice Tests the `symbol` function always returns the correct value.
    function testFuzz_symbol_succeeds(string memory _symbol) public {
        SuperchainERC20 _newSuperchainERC20 = _deploySuperchainERC20Proxy(REMOTE_TOKEN, NAME, _symbol, DECIMALS);
        assertEq(_newSuperchainERC20.symbol(), _symbol);
    }

    /// @notice Tests that the `supportsInterface` function returns true for the `ISuperchainERC20` interface.
    function test_supportInterface_succeeds() public view {
        assertTrue(superchainERC20.supportsInterface(type(IERC165).interfaceId));
        assertTrue(superchainERC20.supportsInterface(type(ISuperchainERC20Extension).interfaceId));
    }

    /// @notice Tests that the `supportsInterface` function returns false for any other interface than the
    /// `ISuperchainERC20` one.
    function testFuzz_supportInterface_returnFalse(bytes4 _interfaceId) public view {
        vm.assume(_interfaceId != type(IERC165).interfaceId);
        vm.assume(_interfaceId != type(ISuperchainERC20Extension).interfaceId);
        assertFalse(superchainERC20.supportsInterface(_interfaceId));
    }
}
