// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { ISequencerFeeVault } from "interfaces/L2/ISequencerFeeVault.sol";

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

/// @title SequencerFeeVault_TestInit
/// @notice Test initialization contract for SequencerFeeVault tests.
abstract contract SequencerFeeVault_TestInit is FeeVault_TestInit {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().sequencerFeeVaultRecipient();
        feeVaultName = "SequencerFeeVault";
        minWithdrawalAmount = deploy.cfg().sequencerFeeVaultMinimumWithdrawalAmount();
        feeVault = IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET));
    }
}

/// @title SequencerFeeVault_Constructor_Test
/// @notice Test contract for the SequencerFeeVault constructor functionality
contract SequencerFeeVault_Constructor_Test is SequencerFeeVault_TestInit, FeeVault_Constructor_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_Constructor_Test) {
        SequencerFeeVault_TestInit.setUp();
    }

    /// @notice Test specific to SequencerFeeVault l1FeeWallet functionality
    function test_constructor_l1FeeWallet_succeeds() external view {
        assertEq(ISequencerFeeVault(payable(address(feeVault))).l1FeeWallet(), recipient);
    }
}

/// @title SequencerFeeVault_Receive_Test
/// @notice Test contract for the SequencerFeeVault receive functionality
contract SequencerFeeVault_Receive_Test is SequencerFeeVault_TestInit, FeeVault_Receive_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_Receive_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}

/// @title SequencerFeeVault_Withdraw_Test
/// @notice Test contract for the SequencerFeeVault withdraw functionality
contract SequencerFeeVault_Withdraw_Test is SequencerFeeVault_TestInit, FeeVault_Withdraw_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_Withdraw_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}

/// @title SequencerFeeVault_SetMinWithdrawalAmount_Test
/// @notice Test contract for the SequencerFeeVault setMinWithdrawalAmount functionality
contract SequencerFeeVault_SetMinWithdrawalAmount_Test is
    SequencerFeeVault_TestInit,
    FeeVault_SetMinWithdrawalAmount_Test
{
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_SetMinWithdrawalAmount_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}

/// @title SequencerFeeVault_SetRecipient_Test
/// @notice Test contract for the SequencerFeeVault setRecipient functionality
contract SequencerFeeVault_SetRecipient_Test is SequencerFeeVault_TestInit, FeeVault_SetRecipient_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_SetRecipient_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}

/// @title SequencerFeeVault_SetWithdrawalNetwork_Test
/// @notice Test contract for the SequencerFeeVault setWithdrawalNetwork functionality
contract SequencerFeeVault_SetWithdrawalNetwork_Test is SequencerFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_SetWithdrawalNetwork_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}

/// @title SequencerFeeVault_Getters_Test
/// @notice Test contract for the SequencerFeeVault getter functionality
contract SequencerFeeVault_Getters_Test is SequencerFeeVault_TestInit, FeeVault_Getters_Test {
    function setUp() public override(SequencerFeeVault_TestInit, FeeVault_Getters_Test) {
        SequencerFeeVault_TestInit.setUp();
    }
}