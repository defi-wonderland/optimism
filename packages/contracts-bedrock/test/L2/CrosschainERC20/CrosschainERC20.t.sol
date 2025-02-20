// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contracts
import { CrosschainERC20 } from "src/L2/CrosschainERC20/CrosschainERC20.sol";
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { IERC7802, IERC165 } from "interfaces/L2/IERC7802.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Testing utilities
import { Test } from "forge-std/Test.sol";

/// @title CrosschainERC20Test
/// @notice Contract for testing the CrosschainERC20 contract.
contract CrosschainERC20Test is Test {
    CrosschainERC20 public _crosschainERC20;
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant SUPERCHAIN_TOKEN_BRIDGE = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address internal _owner = makeAddr("owner");

    /// @notice Sets up the test suite.
    function setUp() public {
        _crosschainERC20 = new CrosschainERC20("Test", "TST", _owner);
    }

    /// @notice Tests the `allowance` function when the spender is Permit2.
    function testFuzz_allowance_whenSpentFromPermit2_succeeds(address _caller) public {
        // Ensure the owner is neither Permit2 nor the zero address
        vm.assume(_caller != _PERMIT2 && _caller != address(0));

        // Assert that the allowance is the maximum when the owner is Permit2
        assertEq(_crosschainERC20.allowance(_caller, _PERMIT2), type(uint256).max);
    }

    /// @notice Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_crosschainMint_callerNotBridge_reverts(address _caller, address _to, uint256 _amount) public {
        // Bound `caller` to not be the zero address
        vm.assume(_caller != ZERO_ADDRESS);

        // Bound `to` to not be the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Ensure the caller is not the bridge
        vm.assume(_caller != SUPERCHAIN_TOKEN_BRIDGE);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _crosschainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, 0);

        // Expect the revert with `NotHighEnoughLimits` selector
        vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);

        // Call the `mint` function with the non-bridge caller
        vm.prank(_caller);
        _crosschainERC20.crosschainMint(_to, _amount);
    }

    /// @notice Tests the `crosschainMint` succeeds.
    function testFuzz_crosschainMint_succeeds(address _to, uint256 _amount) public {
        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _crosschainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, 0);

        // Mint the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _crosschainERC20.crosschainMint(_to, _amount);

        // Assert that the tokens were minted
        assertEq(_crosschainERC20.balanceOf(_to), _amount);
    }

    /// @notice Tests the `burn` function reverts when the caller is not the bridge.
    function testFuzz_crosschainBurn_callerNotBridge_reverts(address _caller, address _from, uint256 _amount) public {
        // Ensure `from` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Ensure the caller is not the zero address
        vm.assume(_caller != ZERO_ADDRESS);

        // Ensure the caller is not the bridge
        vm.assume(_caller != SUPERCHAIN_TOKEN_BRIDGE && _caller != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _crosschainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, _amount);

        // Mint tokens to the `from` address
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _crosschainERC20.crosschainMint(_from, _amount);

        // Approve the caller to spend the tokens
        vm.prank(_from);
        _crosschainERC20.approve(_caller, _amount);

        // Expect the revert with `NotHighEnoughLimits` selector
        vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);

        // Call the `burn` function with the non-bridge caller
        vm.prank(_caller);
        _crosschainERC20.crosschainBurn(_from, _amount);
    }

    /// @notice Tests the `crosschainBurn` succeeds.
    function testFuzz_crosschainBurn_succeeds(address _from, uint256 _amount) public {
        // Ensure `_to` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _crosschainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, _amount);

        // Mint the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _crosschainERC20.crosschainMint(_from, _amount);

        // Approve the Superchain Token Bridge to spend the tokens
        vm.prank(_from);
        _crosschainERC20.approve(SUPERCHAIN_TOKEN_BRIDGE, _amount);

        // Burn the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _crosschainERC20.crosschainBurn(_from, _amount);

        // Assert that the tokens were burned
        assertEq(_crosschainERC20.balanceOf(_from), 0);
    }

    /// @notice Tests that the `supportsInterface` function returns true for the `IERC7802` interface.
    function test_supportInterface_succeeds() public view {
        assertTrue(_crosschainERC20.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_crosschainERC20.supportsInterface(type(IERC7802).interfaceId));
        assertTrue(_crosschainERC20.supportsInterface(type(IERC20).interfaceId));
        assertTrue(_crosschainERC20.supportsInterface(type(IXERC20).interfaceId));
    }

    /// @notice Tests that the `supportsInterface` function returns false for any other interface than the
    /// `IERC7802` one.
    function testFuzz_supportInterface_works(bytes4 _interfaceId) public view {
        vm.assume(_interfaceId != type(IERC165).interfaceId);
        vm.assume(_interfaceId != type(IERC7802).interfaceId);
        vm.assume(_interfaceId != type(IERC20).interfaceId);
        vm.assume(_interfaceId != type(IXERC20).interfaceId);
        assertFalse(_crosschainERC20.supportsInterface(_interfaceId));
    }
}
