// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

// Target contract dependencies
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { IERC7802, IERC165 } from "interfaces/L2/IERC7802.sol";

// Target contract
import { ERC7802Adapter } from "src/L2/XSuperchainERC20/ERC7802Adapter.sol";

contract ERC7802AdapterTest is Test {
    address internal BRIDGE = makeAddr("bridge");
    address internal XERC20 = makeAddr("XERC20");

    ERC7802Adapter adapter;

    /// @notice Sets up the test suite.
    function setUp() public {
        adapter = new ERC7802Adapter(IXERC20(XERC20), BRIDGE);
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Tests the `constructor` sets the `XERC20` contract.
    function test_constructor_setsXERC20() public {
        assertEq(address(adapter.XERC20()), XERC20);
    }

    /// @notice Tests the `crosschainMint` reverts when the caller is not the bridge.
    function testFuzz_crosschainMint_callerIsNotBridge_reverts(address _caller) public {
        vm.assume(_caller != BRIDGE);

        vm.expectRevert(Unauthorized.selector);
        adapter.crosschainMint(address(0), 100);
    }

    /// @notice Tests the `crosschainMint` succeeds and emits the `CrosschainMint` event.
    function testFuzz_crosschainMint_mintXERC20_succeeds(address _to, uint256 _amount) public {
        // Look for the emit of the `CrosschainMint` event
        vm.expectEmit(address(adapter));
        emit IERC7802.CrosschainMint(_to, _amount, BRIDGE);

        // Ensure the adapter successfully calls the `mint` function of the `XERC20` contract
        _mockAndExpect(XERC20, abi.encodeCall(IXERC20.mint, (_to, _amount)), "");

        // Call the `mint` function with the bridge caller
        vm.prank(BRIDGE);
        adapter.crosschainMint(_to, _amount);
    }

    /// @notice Tests the `crosschainBurn` reverts when the caller is not the bridge.
    function testFuzz_crosschainBurn_callerIsNotBridge_reverts(address _caller) public {
        vm.assume(_caller != BRIDGE);

        vm.expectRevert(Unauthorized.selector);
        adapter.crosschainBurn(address(0), 100);
    }

    /// @notice Tests the `crosschainBurn` succeeds and emits the `CrosschainBurn` event.
    function testFuzz_crosschainBurn_burnXERC20_succeeds(address _from, uint256 _amount) public {
        // Look for the emit of the `CrosschainBurn` event
        vm.expectEmit(address(adapter));
        emit IERC7802.CrosschainBurn(_from, _amount, BRIDGE);

        // Ensure the adapter successfully calls the `burn` function of the `XERC20` contract
        _mockAndExpect(XERC20, abi.encodeCall(IXERC20.burn, (_from, _amount)), "");

        // Call the `burn` function with the bridge caller
        vm.prank(BRIDGE);
        adapter.crosschainBurn(_from, _amount);
    }

    /// @notice Tests that the `supportsInterface` function returns true for the `IERC7802` interface.
    function test_supportInterface_succeeds() public view {
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC7802).interfaceId));
    }
}