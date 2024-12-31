// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Constants } from "src/libraries/Constants.sol";

// Test the implementations of the FeeVault
contract FeeVault_Test is CommonTest {
    /// @dev Tests that the constructor sets the correct values.
    function test_constructor_l1FeeVault_succeeds() external view {
        assertEq(l1FeeVault.RECIPIENT(), deploy.cfg().l1FeeVaultRecipient());
        assertEq(l1FeeVault.recipient(), deploy.cfg().l1FeeVaultRecipient());
        assertEq(l1FeeVault.MIN_WITHDRAWAL_AMOUNT(), deploy.cfg().l1FeeVaultMinimumWithdrawalAmount());
        assertEq(l1FeeVault.minWithdrawalAmount(), deploy.cfg().l1FeeVaultMinimumWithdrawalAmount());
        assertEq(uint8(l1FeeVault.WITHDRAWAL_NETWORK()), uint8(Types.WithdrawalNetwork.L1));
        assertEq(uint8(l1FeeVault.withdrawalNetwork()), uint8(Types.WithdrawalNetwork.L1));
    }

    /// @dev Tests that the setConfig function in l1Block  sets the correct values.
    function test_setConfig_succeeds(address _recipient, uint88 _amount, uint8 _networkSeed) external {
        Types.WithdrawalNetwork _network = Types.WithdrawalNetwork(bound(_networkSeed, 0, 1));
        bytes32 l1FeeVaultConfig = Encoding.encodeFeeVaultConfig(_recipient, _amount, _network);

        vm.startPrank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(Types.ConfigType.L1_FEE_VAULT_CONFIG, abi.encode(l1FeeVaultConfig));
        vm.stopPrank();

        assertEq(l1FeeVault.RECIPIENT(), _recipient);
        assertEq(l1FeeVault.recipient(), _recipient);
        assertEq(l1FeeVault.MIN_WITHDRAWAL_AMOUNT(), _amount);
        assertEq(l1FeeVault.minWithdrawalAmount(), _amount);
        assertEq(uint8(l1FeeVault.WITHDRAWAL_NETWORK()), uint8(_network));
        assertEq(uint8(l1FeeVault.withdrawalNetwork()), uint8(_network));
    }
}
