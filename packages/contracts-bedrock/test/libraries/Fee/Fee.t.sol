// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test, console2 } from "forge-std/Test.sol";
import { Fee } from "src/libraries/Fee.sol";

contract Fee_Test is Test {
    struct TestSet {
        Case[] cases;
    }

    struct Case {
        uint256 expected;
        Input inputs;
    }

    struct Input {
        uint256 amount;
        uint256 baseFee;
        uint256 curveExponent;
        uint256 maxFeePercentage;
        uint256 maxPermittedAmount;
    }

    function test_calculateFee() public view {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/libraries/Fee/Fee.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        TestSet memory testSet = abi.decode(data, (TestSet));

        for (uint256 i = 0; i < testSet.cases.length; i++) {
            uint256 fee = Fee.calculateFee(
                testSet.cases[i].inputs.amount,
                testSet.cases[i].inputs.maxPermittedAmount,
                testSet.cases[i].inputs.curveExponent,
                testSet.cases[i].inputs.maxFeePercentage,
                testSet.cases[i].inputs.baseFee
            );

            // Allow for 0.1% error
            assertApproxEqRel(fee, testSet.cases[i].expected, 1e15);
        }
    }
}
