// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Base, UnitNames, UnitMintBurn, UnitCreateParams } from "@xERC20/test/unit/XERC20.t.sol";
import { SuperchainERC20Test } from "test/L2/SuperchainERC20.t.sol";
import { MockXSuperchainERC20Implementation } from "test/mocks/XSuperchainERC20Implementation.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";

/// @title XSuperchainERC20Test
/// @notice Contract for testing the XSuperchainERC20 contract.
contract XSuperchainERC20Test is UnitNames, UnitMintBurn, UnitCreateParams, SuperchainERC20Test {
    MockXSuperchainERC20Implementation public _xSuperchainERC20;
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Sets up the test suite.
    ///
    /// @dev We need to override the `setUp` function to use the `MockXSuperchainERC20Implementation` contract
    /// @dev instead of the `xERC20` and `SuperchainERC20` contracts.
    function setUp() public override(Base, SuperchainERC20Test) {
        _xSuperchainERC20 = new MockXSuperchainERC20Implementation("Test", "TST", _owner);
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
}
