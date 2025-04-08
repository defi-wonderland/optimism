// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { NUTExecutor } from "src/L2/NUTExecutor.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { OperatorFeeVault } from "src/L2/OperatorFeeVault.sol";
import { GasPriceOracle } from "src/L2/GasPriceOracle.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";

contract IsthmusNUTExecutor_1 is NUTExecutor {
    function execute() external override returns (bytes memory returnData_) {
        /**
         * Network Upgrade Transactions
         * L1Block deployment
         * GasPriceOracle deployment
         * Operator Fee vault deployment
         * Update L1Block Proxy ERC-1967 Implementation
         * Update GasPriceOracle Proxy ERC-1967 Implementation
         * Update Operator Fee vault Proxy ERC-1967 Implementation
         * GasPriceOracle Enable Isthmus
         * EIP-2935 Contract Deployment
         */

        // 1. L1Block deployment
        address l1BlockImpl = address(new L1Block());

        // 2. GasPriceOracle deployment
        address gasPriceOracleImpl = address(new GasPriceOracle());

        // 3. Operator Fee vault deployment
        address operatorFeeVaultImpl = address(new OperatorFeeVault());

        // 4. Update L1Block Proxy ERC-1967 Implementation
        IProxy(payable(Predeploys.L1_BLOCK_ATTRIBUTES)).upgradeTo(l1BlockImpl);

        // 6. Update Operator Fee vault Proxy ERC-1967 Implementation
        IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).upgradeTo(operatorFeeVaultImpl);

        // 5. Update GasPriceOracle Proxy ERC-1967 Implementation
        IProxy(payable(Predeploys.GAS_PRICE_ORACLE)).upgradeTo(gasPriceOracleImpl);
    }
}
