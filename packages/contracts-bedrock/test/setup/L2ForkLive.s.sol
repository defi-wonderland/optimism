// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { NUTExecutor } from "src/L2/NUTExecutor.sol";
import { IsthmusNUTExecutor_1 } from "src/L2/IsthmusNutExecutor_1.sol";
import { IsthmusNUTExecutor_2 } from "src/L2/IsthmusNutExecutor_2.sol";
import { Constants } from "src/libraries/Constants.sol";

contract L2ForkLive is Script {
    function run() public {
        // TODO: Add more executors for each network upgrade
        // TODO: Heuristic to determine what upgrades to apply based on the block number (?)
        NUTExecutor[] memory nutExecutors = new NUTExecutor[](2);
        nutExecutors[0] = new IsthmusNUTExecutor_1();
        nutExecutors[1] = new IsthmusNUTExecutor_2();

        // It boils down to this:
        // - We need to make `address(0)`, Proxy Admin or Depositor Account perform a delegatecall in the Go scripts
        // - In the case of OPCM it works because multisig is able to make a delegatecall to the OPCM
        bytes memory code = vm.getDeployedCode("L2ForkLive.s.sol:DummyExecutor");
        address prank = address(0);
        vm.etch(prank, code);
        vm.store(prank, bytes32(0), bytes32(uint256(uint160(address(nutExecutors[0])))));
        vm.label(prank, "DummyExecutor:ProxyOwner");
        DummyExecutor(prank).execute();
        // clear the code
        vm.etch(prank, "");

        prank = Constants.DEPOSITOR_ACCOUNT;
        vm.etch(prank, code);
        vm.store(prank, bytes32(0), bytes32(uint256(uint160(address(nutExecutors[1])))));
        vm.label(prank, "DummyExecutor:Depositor");
        DummyExecutor(prank).execute();
        // clear the code
        vm.etch(prank, "");
    }
}

contract DummyExecutor {
    address internal _nutExecutor;

    function execute() external returns (bool, bytes memory) {
        bytes memory data = abi.encodeCall(DummyExecutor.execute, ());
        (bool success, bytes memory result) = _nutExecutor.delegatecall(data);
        return (success, result);
    }
}
