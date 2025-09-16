// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { FeeVault_Test } from "test/L2/FeeVault.t.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title BaseFeeVault_Test
/// @notice Test contract for the BaseFeeVault contract's functionality
contract BaseFeeVault_Test is FeeVault_Test {
    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().baseFeeVaultRecipient();
        feeVaultName = "BaseFeeVault";
        minWithdrawalAmount = deploy.cfg().baseFeeVaultMinimumWithdrawalAmount();
        feeVault = IFeeVault(payable(Predeploys.BASE_FEE_VAULT));
    }

    // Not using cfg().baseFeeVaultRecipient() bc the impl address has some logic that reverts when receiving fees
    function test_withdraw_toL2_succeeds() public virtual override {
        // Update the recipient to a different address
        recipient = makeAddr("recipient");
        vm.prank(IProxyAdmin(Predeploys.PROXY_ADMIN).owner());
        feeVault.setRecipient(recipient);
        assertEq(feeVault.recipient(), recipient);

        // Run the test
        super.test_withdraw_toL2_succeeds();
    }
}
