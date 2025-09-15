// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { FeeVault_Test } from "test/L2/FeeVault.t.sol";

/// @title L1FeeVault_Test
/// @notice Reusable test initialization for `SequencerFeeVault` tests.
contract L1FeeVault_Test is FeeVault_Test {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().l1FeeVaultRecipient();
        feeVaultName = "L1FeeVault";
        minWithdrawalAmount = deploy.cfg().l1FeeVaultMinimumWithdrawalAmount();
        expectedWithdrawalNetwork = Types.WithdrawalNetwork.L1;
        feeVault = IFeeVault(payable(Predeploys.L1_FEE_VAULT));
    }
}
