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

/// @title BaseFeeVault_TestInit
/// @notice Test initialization contract for BaseFeeVault tests.
abstract contract BaseFeeVault_TestInit is FeeVault_TestInit {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().baseFeeVaultRecipient();
        feeVaultName = "BaseFeeVault";
        minWithdrawalAmount = deploy.cfg().baseFeeVaultMinimumWithdrawalAmount();
        feeVault = IFeeVault(payable(Predeploys.BASE_FEE_VAULT));
        // Current recipient is a contract that reverts when receiving fees, so etching empty bytes to it
        vm.etch(recipient, hex"");
    }
}

/// @title BaseFeeVault_Constructor_Test
/// @notice Test contract for the BaseFeeVault constructor functionality
contract BaseFeeVault_Constructor_Test is BaseFeeVault_TestInit, FeeVault_Constructor_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_Constructor_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_Receive_Test
/// @notice Test contract for the BaseFeeVault receive functionality
contract BaseFeeVault_Receive_Test is BaseFeeVault_TestInit, FeeVault_Receive_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_Receive_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_Withdraw_Test
/// @notice Test contract for the BaseFeeVault withdraw functionality
contract BaseFeeVault_Withdraw_Test is BaseFeeVault_TestInit, FeeVault_Withdraw_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_Withdraw_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_SetMinWithdrawalAmount_Test
/// @notice Test contract for the BaseFeeVault setMinWithdrawalAmount functionality
contract BaseFeeVault_SetMinWithdrawalAmount_Test is BaseFeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_SetRecipient_Test
/// @notice Test contract for the BaseFeeVault setRecipient functionality
contract BaseFeeVault_SetRecipient_Test is BaseFeeVault_TestInit, FeeVault_SetRecipient_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_SetRecipient_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_SetWithdrawalNetwork_Test
/// @notice Test contract for the BaseFeeVault setWithdrawalNetwork functionality
contract BaseFeeVault_SetWithdrawalNetwork_Test is BaseFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}

/// @title BaseFeeVault_Getters_Test
/// @notice Test contract for the BaseFeeVault getter functionality
contract BaseFeeVault_Getters_Test is BaseFeeVault_TestInit, FeeVault_Getters_Test {
    function setUp() public override(BaseFeeVault_TestInit, FeeVault_Getters_Test) {
        BaseFeeVault_TestInit.setUp();
    }
}
