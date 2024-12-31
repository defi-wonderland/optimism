// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Types } from "src/libraries/Types.sol";
import { Constants } from "src/libraries/Constants.sol";

// Test the implementations of the FeeVault
contract FeeVault_Test is CommonTest {
    /// @dev Tests that the constructor sets the correct values.
    function test_constructor_baseFeeVault_succeeds() external view {
        assertEq(baseFeeVault.RECIPIENT(), deploy.cfg().baseFeeVaultRecipient());
        assertEq(baseFeeVault.recipient(), deploy.cfg().baseFeeVaultRecipient());
        assertEq(baseFeeVault.MIN_WITHDRAWAL_AMOUNT(), deploy.cfg().baseFeeVaultMinimumWithdrawalAmount());
        assertEq(baseFeeVault.minWithdrawalAmount(), deploy.cfg().baseFeeVaultMinimumWithdrawalAmount());
        assertEq(uint8(baseFeeVault.WITHDRAWAL_NETWORK()), uint8(Types.WithdrawalNetwork.L1));
        assertEq(uint8(baseFeeVault.withdrawalNetwork()), uint8(Types.WithdrawalNetwork.L1));
    }

    /// @dev Tests that the setConfig function in l1Block  sets the correct values.
    function test_setConfig_succeeds(address _recipient, uint88 _amount, uint8 _networkSeed) external {
        Types.WithdrawalNetwork _network = Types.WithdrawalNetwork(bound(_networkSeed, 0, 1));
        bytes32 baseFeeVaultConfig = Encoding.encodeFeeVaultConfig(_recipient, _amount, _network);

        vm.startPrank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(Types.ConfigType.BASE_FEE_VAULT_CONFIG, abi.encode(baseFeeVaultConfig));
        vm.stopPrank();

        assertEq(baseFeeVault.RECIPIENT(), _recipient);
        assertEq(baseFeeVault.recipient(), _recipient);
        assertEq(baseFeeVault.MIN_WITHDRAWAL_AMOUNT(), _amount);
        assertEq(baseFeeVault.minWithdrawalAmount(), _amount);
        assertEq(uint8(baseFeeVault.WITHDRAWAL_NETWORK()), uint8(_network));
        assertEq(uint8(baseFeeVault.withdrawalNetwork()), uint8(_network));
    }
}
