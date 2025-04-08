// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { NUTExecutor } from "src/L2/NUTExecutor.sol";
import { IsthmusNUTExecutor_1 } from "src/L2/IsthmusNutExecutor_1.sol";
import { IsthmusNUTExecutor_2 } from "src/L2/IsthmusNutExecutor_2.sol";
import { Constants } from "src/libraries/Constants.sol";

contract L2ForkLive is Script {
    struct NUTExecutorInfo {
        bytes byteCode;
        address sender;
    }

    function run() public {
        // TODO: Add more executors for each network upgrade
        // TODO: Heuristic to determine what upgrades to apply based on the block number (?)
        NUTExecutorInfo[] memory nutExecutors = new NUTExecutorInfo[](2);
        nutExecutors[0] = NUTExecutorInfo({ byteCode: type(IsthmusNUTExecutor_1).runtimeCode, sender: address(0) });
        nutExecutors[1] =
            NUTExecutorInfo({ byteCode: type(IsthmusNUTExecutor_2).runtimeCode, sender: Constants.DEPOSITOR_ACCOUNT });

        for (uint256 i = 0; i < nutExecutors.length; i++) {
            vm.etch(address(nutExecutors[i].sender), nutExecutors[i].byteCode);

            NUTExecutor(address(nutExecutors[i].sender)).execute();

            // Reset the bytecode to empty
            vm.etch(address(nutExecutors[i].sender), "");
        }
    }
}
