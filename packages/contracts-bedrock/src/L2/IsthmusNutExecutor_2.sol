// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { NUTExecutor } from "src/L2/NUTExecutor.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { OperatorFeeVault } from "src/L2/OperatorFeeVault.sol";
import { GasPriceOracle } from "src/L2/GasPriceOracle.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { console2 } from "forge-std/console2.sol";
import { Constants } from "src/libraries/Constants.sol";
import { IGasPriceOracle } from "interfaces/L2/IGasPriceOracle.sol";

contract IsthmusNUTExecutor_2 is NUTExecutor {
    function execute() external override returns (bytes memory returnData_) {
        // 7. GasPriceOracle Enable Isthmus
        IGasPriceOracle(Predeploys.GAS_PRICE_ORACLE).setIsthmus();
    }
}
