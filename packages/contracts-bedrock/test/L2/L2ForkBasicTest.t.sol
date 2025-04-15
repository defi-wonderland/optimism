// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CommonTest } from "test/setup/CommonTest.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

contract L2ForkBasicTest is CommonTest {
    function test_sanity() external view {
        assert(keccak256(bytes(ISemver(Predeploys.L1_BLOCK_ATTRIBUTES).version())) == keccak256(bytes("1.6.0")));
    }
}
