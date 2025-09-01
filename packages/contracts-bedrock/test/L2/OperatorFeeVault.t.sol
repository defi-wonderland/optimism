// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title OperatorFeeVault_Constructor_Test
/// @notice Tests the `constructor` of the `OperatorFeeVault` contract.
contract OperatorFeeVault_Constructor_Test is CommonTest {
    /// @notice Tests that the constructor sets the correct values.
    function test_constructor_operatorFeeVault_succeeds() external view {
        assertEq(operatorFeeVault.RECIPIENT(), deploy.cfg().operatorFeeVaultRecipient());
        assertEq(operatorFeeVault.recipient(), deploy.cfg().operatorFeeVaultRecipient());
        assertEq(operatorFeeVault.MIN_WITHDRAWAL_AMOUNT(), deploy.cfg().operatorFeeVaultMinimumWithdrawalAmount());
        assertEq(operatorFeeVault.minWithdrawalAmount(), deploy.cfg().operatorFeeVaultMinimumWithdrawalAmount());
        assertEq(
            uint8(operatorFeeVault.WITHDRAWAL_NETWORK()),
            uint8(Types.WithdrawalNetwork(deploy.cfg().operatorFeeVaultWithdrawalNetwork()))
        );
        assertEq(
            uint8(operatorFeeVault.withdrawalNetwork()),
            uint8(Types.WithdrawalNetwork(deploy.cfg().operatorFeeVaultWithdrawalNetwork()))
        );
    }
}
