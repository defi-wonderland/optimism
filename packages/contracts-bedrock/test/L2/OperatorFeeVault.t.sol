// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Test contracts
import {
    FeeVault_TestInit,
    FeeVault_Constructor_Test,
    FeeVault_Receive_Test,
    FeeVault_Withdraw_Test,
    FeeVault_SetMinWithdrawalAmount_Test,
    FeeVault_SetRecipient_Test,
    FeeVault_SetWithdrawalNetwork_Test,
    FeeVault_Getters_Test
} from "test/L2/FeeVault.t.sol";

/// @title OperatorFeeVault_TestInit
/// @notice Test initialization contract for OperatorFeeVault tests.
abstract contract OperatorFeeVault_TestInit is FeeVault_TestInit {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().operatorFeeVaultRecipient();
        feeVaultName = "OperatorFeeVault";
        minWithdrawalAmount = deploy.cfg().operatorFeeVaultMinimumWithdrawalAmount();
        feeVault = IFeeVault(payable(Predeploys.OPERATOR_FEE_VAULT));
    }
}

/// @title OperatorFeeVault_Constructor_Test
/// @notice Test contract for the OperatorFeeVault constructor functionality
contract OperatorFeeVault_Constructor_Test is OperatorFeeVault_TestInit, FeeVault_Constructor_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_Constructor_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_Receive_Test
/// @notice Test contract for the OperatorFeeVault receive functionality
contract OperatorFeeVault_Receive_Test is OperatorFeeVault_TestInit, FeeVault_Receive_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_Receive_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_Withdraw_Test
/// @notice Test contract for the OperatorFeeVault withdraw functionality
contract OperatorFeeVault_Withdraw_Test is OperatorFeeVault_TestInit, FeeVault_Withdraw_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_Withdraw_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_SetMinWithdrawalAmount_Test
/// @notice Test contract for the OperatorFeeVault setMinWithdrawalAmount functionality
contract OperatorFeeVault_SetMinWithdrawalAmount_Test is
    OperatorFeeVault_TestInit,
    FeeVault_SetMinWithdrawalAmount_Test
{
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_SetRecipient_Test
/// @notice Test contract for the OperatorFeeVault setRecipient functionality
contract OperatorFeeVault_SetRecipient_Test is OperatorFeeVault_TestInit, FeeVault_SetRecipient_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_SetRecipient_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_SetWithdrawalNetwork_Test
/// @notice Test contract for the OperatorFeeVault setWithdrawalNetwork functionality
contract OperatorFeeVault_SetWithdrawalNetwork_Test is OperatorFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}

/// @title OperatorFeeVault_Getters_Test
/// @notice Test contract for the OperatorFeeVault getter functionality
contract OperatorFeeVault_Getters_Test is OperatorFeeVault_TestInit, FeeVault_Getters_Test {
    function setUp() public override(OperatorFeeVault_TestInit, FeeVault_Getters_Test) {
        OperatorFeeVault_TestInit.setUp();
    }
}