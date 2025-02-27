// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Libraries
import { Test } from "forge-std/Test.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { IL2ProxyAdmin } from "interfaces/L2/IL2ProxyAdmin.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

contract IsthmusUpgradeTest is Test {
    bytes32 internal _salt = DeployUtils.DEFAULT_SALT;

    function setUp() public {
        if (!isForkTest()) {
            return;
        }

        vm.createSelectFork(vm.envString("FORK_RPC_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
    }

    /// @notice Indicates whether a test is running against a forked production network.
    function isForkTest() public view returns (bool) {
        return vm.envOr("FORK_TEST", false);
    }

    /// @dev This test is used to test the isthmus upgrade flow.
    ///      It is a forked test to be able to test the correct values for the fee vaults once the isthmus upgrade is
    ///      complete.
    function test_setIsthmusUpgrade() external {
        vm.skip(!isForkTest());

        /// 1. Deploy the L1Block contract
        IL1Block l1Block =
            IL1Block(DeployUtils.createDeterministic({ _name: "L1Block", _args: bytes(""), _salt: _salt }));

        IL2ProxyAdmin proxyAdmin = IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN);

        /// 2. Upgrade the L1Block contract
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(payable(Predeploys.L1_BLOCK_ATTRIBUTES), address(l1Block));

        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), false);

        /// 3. Perform the isthmus upgrade
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).setIsthmus();

        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), true);

        // Obtain the receipient, min withdrawal amount, and network for the fee vaults
        address baseFeeVaultRecipient = IFeeVault(payable(Predeploys.BASE_FEE_VAULT)).RECIPIENT();
        uint256 baseFeeVaultMinWithdrawalAmount = IFeeVault(payable(Predeploys.BASE_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();

        address l1FeeVaultRecipient = IFeeVault(payable(Predeploys.L1_FEE_VAULT)).RECIPIENT();
        uint256 l1FeeVaultMinWithdrawalAmount = IFeeVault(payable(Predeploys.L1_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();

        address sequencerFeeVaultRecipient = IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).RECIPIENT();
        uint256 sequencerFeeVaultMinWithdrawalAmount =
            IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).MIN_WITHDRAWAL_AMOUNT();

        // 4. Upgrade the remaining proxies
        address baseFeeVault =
            DeployUtils.createDeterministic({ _name: "BaseFeeVault", _args: bytes(""), _salt: _salt });
        address l1FeeVault = DeployUtils.createDeterministic({ _name: "L1FeeVault", _args: bytes(""), _salt: _salt });
        address sequencerFeeVault =
            DeployUtils.createDeterministic({ _name: "SequencerFeeVault", _args: bytes(""), _salt: _salt });

        vm.startPrank(proxyAdmin.owner());
        proxyAdmin.upgrade(payable(Predeploys.BASE_FEE_VAULT), address(baseFeeVault));
        proxyAdmin.upgrade(payable(Predeploys.L1_FEE_VAULT), address(l1FeeVault));
        proxyAdmin.upgrade(payable(Predeploys.SEQUENCER_FEE_WALLET), address(sequencerFeeVault));
        vm.stopPrank();

        {
            bytes memory baseFeeVaultConfig =
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.BASE_FEE_VAULT_CONFIG);

            assertEq(
                abi.decode(baseFeeVaultConfig, (bytes32)),
                Encoding.encodeFeeVaultConfig(
                    baseFeeVaultRecipient, baseFeeVaultMinWithdrawalAmount, Types.WithdrawalNetwork.L2
                )
            );
        }

        {
            bytes memory l1FeeVaultConfig =
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.L1_FEE_VAULT_CONFIG);

            assertEq(
                abi.decode(l1FeeVaultConfig, (bytes32)),
                Encoding.encodeFeeVaultConfig(
                    l1FeeVaultRecipient, l1FeeVaultMinWithdrawalAmount, Types.WithdrawalNetwork.L2
                )
            );
        }

        {
            bytes memory sequencerFeeVaultConfig =
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG);

            assertEq(
                abi.decode(sequencerFeeVaultConfig, (bytes32)),
                Encoding.encodeFeeVaultConfig(
                    sequencerFeeVaultRecipient, sequencerFeeVaultMinWithdrawalAmount, Types.WithdrawalNetwork.L2
                )
            );
        }
    }
}
