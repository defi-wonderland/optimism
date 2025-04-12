// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CommonTest } from "test/setup/CommonTest.sol";
import { IsthmusNUTExecutor_1 } from "src/L2/IsthmusNutExecutor_1.sol";
import { IsthmusNUTExecutor_2 } from "src/L2/IsthmusNutExecutor_2.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Constants } from "src/libraries/Constants.sol";

interface ContractVersion {
    function version() external view returns (string memory);
}

contract L2ForkBasicTest is CommonTest {
    bytes32 internal constant OWNER_KEY = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    modifier skipUpgrade() {
        // Skip the test for blocks after the fork
        vm.skip(block.number > 134354841);
        _;
    }

    function test_isthmus_nut_executor_1() external skipUpgrade {
        IsthmusNUTExecutor_1 executor = new IsthmusNUTExecutor_1();

        vm.store(Predeploys.L1_BLOCK_ATTRIBUTES, OWNER_KEY, bytes32(uint256(uint160(address(executor)))));
        vm.store(Predeploys.OPERATOR_FEE_VAULT, OWNER_KEY, bytes32(uint256(uint160(address(executor)))));
        vm.store(Predeploys.GAS_PRICE_ORACLE, OWNER_KEY, bytes32(uint256(uint160(address(executor)))));

        executor.execute();

        assertEq(
            keccak256(abi.encodePacked(ContractVersion(Predeploys.L1_BLOCK_ATTRIBUTES).version())),
            keccak256(abi.encodePacked("1.6.0"))
        );

        assertEq(
            keccak256(abi.encodePacked(ContractVersion(Predeploys.OPERATOR_FEE_VAULT).version())),
            keccak256(abi.encodePacked("1.0.0"))
        );

        assertEq(
            keccak256(abi.encodePacked(ContractVersion(Predeploys.GAS_PRICE_ORACLE).version())),
            keccak256(abi.encodePacked("1.4.0"))
        );
    }

    function test_isthmus_nut_executor_2() external skipUpgrade {
        IsthmusNUTExecutor_2 executor = new IsthmusNUTExecutor_2();

        executor.execute();
    }
}
