// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import { UnitNames, UnitMintBurn, UnitCreateParams } from "@xERC20/test/unit/XERC20.t.sol";
import { MockXSuperchainERC20Implementation } from "test/mocks/XSuperchainERC20Implementation.sol";

contract XSuperchainERC20Test is Test, UnitNames, UnitMintBurn, UnitCreateParams {
    function setUp() public override {
        _xerc20 = new MockXSuperchainERC20Implementation("Test", "TST", _owner);
    }
}
