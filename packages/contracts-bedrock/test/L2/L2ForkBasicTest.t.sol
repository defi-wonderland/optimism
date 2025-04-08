// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CommonTest } from "test/setup/CommonTest.sol";

contract L2ForkBasicTest is CommonTest {
    function test_sanity() external view {
        assert(l1Block.operatorFeeConstant() == 0);
    }
}
