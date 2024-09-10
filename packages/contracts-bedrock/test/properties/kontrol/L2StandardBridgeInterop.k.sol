// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { L2StandardBridgeInterop } from "src/L2/L2StandardBridgeInterop.sol";
import { L2StandardBridge } from "src/L2/L2StandardBridge.sol";
import { Test } from "forge-std/Test.sol";

contract L2StandardBridgeInteropKontrol is Test {
    L2StandardBridgeInterop public immutable l2StandardBridgeInterop =
        L2StandardBridgeInterop(payable(Predeploys.L2_STANDARD_BRIDGE));
    address public otherBridge = address(uint160(uint256(keccak256("otherBridge"))));

    // TODO: Implement external computation
    function setUp() public {
        address _l2StandardBridgeInteropImpl = address(new L2StandardBridgeInterop());
        vm.etch(Predeploys.L2_STANDARD_BRIDGE, _l2StandardBridgeInteropImpl.code);

        l2StandardBridgeInterop.initialize(L2StandardBridge(payable(otherBridge)));
    }

    function test_setup() public view {
        assertEq(l2StandardBridgeInterop.version(), "1.11.1-beta.1+interop");
    }

    // TODO: Remove convert prefix
    function prove_convertSetup() public view {
        assertEq(l2StandardBridgeInterop.version(), "1.11.1-beta.1+interop");
    }
}
