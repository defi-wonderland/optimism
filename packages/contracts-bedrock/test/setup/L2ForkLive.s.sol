// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { NUTExecutor } from "src/L2/NUTExecutor.sol";
import { IsthmusNUTExecutor_1 } from "src/L2/IsthmusNutExecutor_1.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { L2ProxyAdmin } from "src/L2/L2ProxyAdmin.sol";

contract L2ForkLive is Script {
    function run() public {
        // PoC: Upgrade L2ProxyAdmin, this would be the last upgrade before implementing the NUTExecutor
        // NOTE: This will not live here
        L2ProxyAdmin proxyAdmin = new L2ProxyAdmin(Constants.DEPOSITOR_ACCOUNT);
        address prank = address(0);
        vm.prank(prank);
        IProxy(payable(Predeploys.PROXY_ADMIN)).upgradeTo(address(proxyAdmin));

        // TODO: Heuristic to determine what upgrades to apply based on the block number (?)
        NUTExecutor[] memory nutExecutors = new NUTExecutor[](1);
        nutExecutors[0] = new IsthmusNUTExecutor_1();

        prank = Constants.DEPOSITOR_ACCOUNT;
        vm.prank(prank, prank);
        L2ProxyAdmin(payable(Predeploys.PROXY_ADMIN)).performDelegateCall(address(nutExecutors[0]));
    }
}
