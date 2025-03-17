// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Constants } from "src/libraries/Constants.sol";

// Test the implementations of the OperatorFeeVault
contract OperatorFeeVault_Test is CommonTest {
    /// @dev Tests that the constructor sets the correct values.
    function test_constructor_operatorFeeVault_succeeds() external view {
        assertEq(operatorFeeVault.RECIPIENT(), Predeploys.BASE_FEE_VAULT);
        assertEq(operatorFeeVault.recipient(), Predeploys.BASE_FEE_VAULT);
        assertEq(operatorFeeVault.MIN_WITHDRAWAL_AMOUNT(), 0);
        assertEq(operatorFeeVault.minWithdrawalAmount(), 0);
        assertEq(uint8(operatorFeeVault.WITHDRAWAL_NETWORK()), uint8(Types.WithdrawalNetwork.L2));
        assertEq(uint8(operatorFeeVault.withdrawalNetwork()), uint8(Types.WithdrawalNetwork.L2));
    }

    /// @dev Tests that the setConfig function in l1Block  sets the correct values.
    function test_setConfig_succeeds(address _recipient, uint88 _amount, uint8 _networkSeed) external {
        Types.WithdrawalNetwork _network = Types.WithdrawalNetwork(bound(_networkSeed, 0, 1));
        bytes32 operatorFeeVaultConfig = Encoding.encodeFeeVaultConfig(_recipient, _amount, _network);

        vm.startPrank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(Types.ConfigType.OPERATOR_FEE_VAULT_CONFIG, abi.encode(operatorFeeVaultConfig));
        vm.stopPrank();

        assertEq(operatorFeeVault.RECIPIENT(), Predeploys.BASE_FEE_VAULT);
        assertEq(operatorFeeVault.recipient(), Predeploys.BASE_FEE_VAULT);
        assertEq(operatorFeeVault.MIN_WITHDRAWAL_AMOUNT(), 0);
        assertEq(operatorFeeVault.minWithdrawalAmount(), 0);
        assertEq(uint8(operatorFeeVault.WITHDRAWAL_NETWORK()), uint8(Types.WithdrawalNetwork.L2));
        assertEq(uint8(operatorFeeVault.withdrawalNetwork()), uint8(Types.WithdrawalNetwork.L2));
    }
}
