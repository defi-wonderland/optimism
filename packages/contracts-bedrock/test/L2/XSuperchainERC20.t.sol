// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import { Base, UnitNames, UnitMintBurn, UnitCreateParams } from "@xERC20/test/unit/XERC20.t.sol";
import { SuperchainERC20Test } from "test/L2/SuperchainERC20.t.sol";
import { MockXSuperchainERC20Implementation } from "test/mocks/XSuperchainERC20Implementation.sol";

contract XSuperchainERC20Test is Test, UnitNames, UnitMintBurn, UnitCreateParams, SuperchainERC20Test {
    function setUp() public override(Base, SuperchainERC20Test) {
        MockXSuperchainERC20Implementation _xSuperchainERC20 = new MockXSuperchainERC20Implementation("Test", "TST", _owner);
        _xerc20 = _xSuperchainERC20;
        superchainERC20 = _xSuperchainERC20;
    }
}
