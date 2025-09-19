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

/// @title L1FeeVault_TestInit
/// @notice Test initialization contract for L1FeeVault tests.
abstract contract L1FeeVault_TestInit is FeeVault_TestInit {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().l1FeeVaultRecipient();
        feeVaultName = "L1FeeVault";
        minWithdrawalAmount = deploy.cfg().l1FeeVaultMinimumWithdrawalAmount();
        feeVault = IFeeVault(payable(Predeploys.L1_FEE_VAULT));
    }
}

/// @title L1FeeVault_Constructor_Test
/// @notice Test contract for the L1FeeVault constructor functionality
contract L1FeeVault_Constructor_Test is L1FeeVault_TestInit, FeeVault_Constructor_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_Constructor_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_Receive_Test
/// @notice Test contract for the L1FeeVault receive functionality
contract L1FeeVault_Receive_Test is L1FeeVault_TestInit, FeeVault_Receive_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_Receive_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_Withdraw_Test
/// @notice Test contract for the L1FeeVault withdraw functionality
contract L1FeeVault_Withdraw_Test is L1FeeVault_TestInit, FeeVault_Withdraw_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_Withdraw_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_SetMinWithdrawalAmount_Test
/// @notice Test contract for the L1FeeVault setMinWithdrawalAmount functionality
contract L1FeeVault_SetMinWithdrawalAmount_Test is L1FeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_SetRecipient_Test
/// @notice Test contract for the L1FeeVault setRecipient functionality
contract L1FeeVault_SetRecipient_Test is L1FeeVault_TestInit, FeeVault_SetRecipient_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_SetRecipient_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_SetWithdrawalNetwork_Test
/// @notice Test contract for the L1FeeVault setWithdrawalNetwork functionality
contract L1FeeVault_SetWithdrawalNetwork_Test is L1FeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test) {
        L1FeeVault_TestInit.setUp();
    }
}

/// @title L1FeeVault_Getters_Test
/// @notice Test contract for the L1FeeVault getter functionality
contract L1FeeVault_Getters_Test is L1FeeVault_TestInit, FeeVault_Getters_Test {
    function setUp() public override(L1FeeVault_TestInit, FeeVault_Getters_Test) {
        L1FeeVault_TestInit.setUp();
    }
}
