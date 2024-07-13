// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

// Target contract
import { SuperchainERC20, CallerNotBridge, ERC20 } from "src/L2/SuperchainERC20.sol";
import { ISuperchainERC20 } from "src/L2/ISuperchainERC20.sol";

/// @title SuperchainERC20Test
/// @dev Contract for testing the SuperchainERC20 contract.
contract SuperchainERC20Test is Test {
    string internal constant NAME = "SuperchainERC20";
    string internal constant SYMBOL = "SCE";
    uint8 internal constant DECIMALS = 18;
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;

    SuperchainERC20 public superchainERC20;

    /// @dev Sets up the test suite.
    function setUp() public {
        superchainERC20 = new SuperchainERC20(NAME, SYMBOL, DECIMALS);
    }

    /// @dev Test that the bridge's constructor sets the correct values.
    function test_constructor_succeeds() public view {
        // Check the name, symbol, and decimals were set correctly
        assertEq(superchainERC20.name(), NAME);
        assertEq(superchainERC20.symbol(), SYMBOL);
        assertEq(superchainERC20.decimals(), DECIMALS);
    }

    /// @dev Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_mint_callerNotBridge_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != BRIDGE);

        // Expect the revert with `CallerNotBridge` selector
        vm.expectRevert(abi.encodeWithSelector(CallerNotBridge.selector));

        // Call the `mint` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.mint(_to, _amount);
    }

    /// @dev Tests the `mint` function reverts when the amount is zero.
    function testFuzz_mint_zeroAddressTo_reverts(uint256 _amount) public {
        // Expect the revert reason "ERC20: mint to the zero address"
        vm.expectRevert("ERC20: mint to the zero address");

        // Call the `mint` function with the zero address
        vm.prank(BRIDGE);
        address _to = address(0);
        superchainERC20.mint(_to, _amount);
    }

    /// @dev Tests the `mint` succeeds and emits the `Mint` event.
    function testFuzz_mint_succeeds(address _to, uint256 _amount) public {
        // Ensure `_to` is not the zero address
        vm.assume(_to != address(0));

        // Get the total supply and balance of `_to` before the mint to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _toBalanceBefore = superchainERC20.balanceOf(_to);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(address(0), _to, _amount);

        // Look for the emit of the `Mint` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.Mint(_to, _amount);

        // Call the `mint` function with the bridge caller
        vm.prank(BRIDGE);
        superchainERC20.mint(_to, _amount);

        // Check the total supply and balance of `_to` after the mint were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(superchainERC20.balanceOf(_to), _toBalanceBefore + _amount);
    }

    /// @dev Tests the `burn` function reverts when the caller is not the bridge.
    function testFuzz_burn_callerNotBridge_reverts(address _caller, address _from, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != BRIDGE);

        // Expect the revert with `CallerNotBridge` selector
        vm.expectRevert(abi.encodeWithSelector(CallerNotBridge.selector));

        // Call the `burn` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.burn(_from, _amount);
    }

    /// @dev Tests the `burn` function reverts when the amount is zero.
    function testFuzz_burn_zeroAddressFrom_reverts(uint256 _amount) public {
        // Expect the revert reason "ERC20: burn from the zero address"
        vm.expectRevert("ERC20: burn from the zero address");

        // Call the `burn` function with the zero address
        vm.prank(BRIDGE);
        address _from = address(0);
        superchainERC20.burn(_from, _amount);
    }

    /// @dev Tests the `burn` succeeds and emits the `Burn` event.
    function testFuzz_burn_succeeds(address _from, uint256 _amount) public {
        // Ensure `_from` is not the zero address
        vm.assume(_from != address(0));

        // Mint some tokens to `_from` so then they can be burned
        vm.prank(BRIDGE);
        superchainERC20.mint(_from, _amount);

        // Get the total supply and balance of `_from` before the burn to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _fromBalanceBefore = superchainERC20.balanceOf(_from);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(_from, address(0), _amount);

        // Look for the emit of the `Burn` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.Burn(_from, _amount);

        // Call the `burn` function with the bridge caller
        vm.prank(BRIDGE);
        superchainERC20.burn(_from, _amount);

        // Check the total supply and balance of `_from` after the burn were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(superchainERC20.balanceOf(_from), _fromBalanceBefore - _amount);
    }
}
