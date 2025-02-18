// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contracts
import { XSuperchainERC20 } from "src/L2/XSuperchainERC20/XSuperchainERC20.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";

// Testing utilities
import { Base, UnitNames, UnitMintBurn, UnitCreateParams } from "@xERC20/test/unit/XERC20.t.sol";
import { SuperchainERC20Test } from "test/L2/SuperchainERC20.t.sol";

/// @title XSuperchainERC20Test
/// @notice Contract for testing the XSuperchainERC20 contract.
contract XSuperchainERC20Test is UnitNames, UnitMintBurn, UnitCreateParams, SuperchainERC20Test {
    XSuperchainERC20 public _xSuperchainERC20;
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Sets up the test suite.
    ///
    /// @dev We need to override the `setUp` function to use the `XSuperchainERC20` contract
    /// instead of the `xERC20` and `SuperchainERC20` contracts.
    function setUp() public override(Base, SuperchainERC20Test) {
        _xSuperchainERC20 = new XSuperchainERC20("Test", "TST", _owner);
        _xerc20 = _xSuperchainERC20;
        superchainERC20 = SuperchainERC20(address(_xSuperchainERC20));
    }

    /// @notice Tests the `allowance` function when the spender is Permit2.
    function testAllowanceWhenSpentFromPermit2(address _owner) public {
        // Ensure the owner is neither Permit2 nor the zero address
        vm.assume(_owner != _PERMIT2 && _owner != address(0));

        // Assert that the allowance is the maximum when the owner is Permit2
        assertEq(_xSuperchainERC20.allowance(_owner, _PERMIT2), type(uint256).max);
    }

    /// @notice Tests the `crosschainMint` succeeds.
    function testFuzz_crosschainMint_succeeds(address _to, uint256 _amount) public override {
        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _xSuperchainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, 0);

        // Mint the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _xSuperchainERC20.crosschainMint(_to, _amount);

        // Assert that the tokens were minted
        assertEq(_xSuperchainERC20.balanceOf(_to), _amount);
    }

    /// @notice Tests the `crosschainBurn` succeeds.
    function testFuzz_crosschainBurn_succeeds(address _from, uint256 _amount) public override {
        // Ensure `_to` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Bound `amount` to not surpass the xERC20 limits
        _amount = bound(_amount, 1, 1e40);

        // Set the limits for the Superchain Token Bridge
        vm.prank(_owner);
        _xSuperchainERC20.setLimits(SUPERCHAIN_TOKEN_BRIDGE, _amount, _amount);

        // Mint the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _xSuperchainERC20.crosschainMint(_from, _amount);

        // Approve the Superchain Token Bridge to spend the tokens
        vm.prank(_from);
        _xSuperchainERC20.approve(SUPERCHAIN_TOKEN_BRIDGE, _amount);

        // Burn the tokens using the ERC7802 interface
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _xSuperchainERC20.crosschainBurn(_from, _amount);

        // Assert that the tokens were burned
        assertEq(_xSuperchainERC20.balanceOf(_from), 0);
    }
}
