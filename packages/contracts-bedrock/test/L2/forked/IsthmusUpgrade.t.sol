// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Test } from "forge-std/Test.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Types } from "src/libraries/Types.sol";
import { Events } from "test/setup/Events.sol";

// Interfaces
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { IL2ProxyAdmin } from "interfaces/L2/IL2ProxyAdmin.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { IERC721Bridge } from "interfaces/universal/IERC721Bridge.sol";
import { IL2CrossDomainMessenger } from "interfaces/L2/IL2CrossDomainMessenger.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { CommonTest } from "test/setup/CommonTest.sol";

contract IsthmusUpgradeTest is CommonTest {
    bytes32 internal _salt = DeployUtils.DEFAULT_SALT;

    // TODO: Make sure isthmus upgrade is not active on the forked network

    /// @dev This test is used to test the isthmus upgrade flow.
    ///      It is a forked test to be able to test the correct values for the fee vaults once the isthmus upgrade is
    ///      complete.
    function test_setIsthmusUpgrade_feeVaults() external {
        vm.skip(!isL2ForkTest());

        /// 1. Deploy the new L1Block implementation contract
        /// 2. Upgrade the L1Block contract
        _upgradeL1Block();
        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), false);

        /// 3. Perform the isthmus upgrade in the L1Block contract
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).setIsthmus();

        // Assert the isthmus upgrade was successful
        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), true);

        // Obtain the receipient, min withdrawal amount, and network for each fee vault from the actual contracts.
        // This is performed before the upgrade since post-isthmus fee vaults get their values from L1Block.

        // Fee Vaults
        address baseFeeVaultRecipient = IFeeVault(payable(Predeploys.BASE_FEE_VAULT)).RECIPIENT();
        uint256 baseFeeVaultMinWithdrawalAmount = IFeeVault(payable(Predeploys.BASE_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();

        address l1FeeVaultRecipient = IFeeVault(payable(Predeploys.L1_FEE_VAULT)).RECIPIENT();
        uint256 l1FeeVaultMinWithdrawalAmount = IFeeVault(payable(Predeploys.L1_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();

        address sequencerFeeVaultRecipient = IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).RECIPIENT();
        uint256 sequencerFeeVaultMinWithdrawalAmount =
            IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).MIN_WITHDRAWAL_AMOUNT();

        // 4. Upgrade the remaining proxies
        _upgradeProxies();

        // Assert the fee vault configs match the pre-isthmus values
        bytes memory baseFeeVaultConfig =
            IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.BASE_FEE_VAULT_CONFIG);
        assert(_checkFeeVaultConfig(baseFeeVaultConfig, baseFeeVaultRecipient, baseFeeVaultMinWithdrawalAmount));

        bytes memory l1FeeVaultConfig =
            IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.L1_FEE_VAULT_CONFIG);
        assert(_checkFeeVaultConfig(l1FeeVaultConfig, l1FeeVaultRecipient, l1FeeVaultMinWithdrawalAmount));

        bytes memory sequencerFeeVaultConfig =
            IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG);
        assert(
            _checkFeeVaultConfig(
                sequencerFeeVaultConfig, sequencerFeeVaultRecipient, sequencerFeeVaultMinWithdrawalAmount
            )
        );
    }

    /// @dev This test is used to test the isthmus upgrade flow.
    ///      It is a forked test to be able to test the correct values for the other contracts once the isthmus upgrade
    ///      is complete.
    function test_setIsthmusUpgrade_otherContracts() external {
        vm.skip(!isL2ForkTest());

        /// 1. Deploy the new L1Block implementation contract
        /// 2. Upgrade the L1Block contract
        _upgradeL1Block();

        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), false);

        /// 3. Perform the isthmus upgrade in the L1Block contract
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).setIsthmus();

        // Assert the isthmus upgrade was successful
        assertEq(IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isIsthmus(), true);

        // Obtain the other messenger, standard bridge, and ERC721 bridge addresses from the actual contracts.
        // This is performed before the upgrade since post-isthmus contracts get their values from L1Block.

        // Cross Domain Messenger
        ICrossDomainMessenger otherMessenger =
            ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).OTHER_MESSENGER();
        // Standard Bridge
        IStandardBridge otherStandardBridge = IStandardBridge(payable(Predeploys.L2_STANDARD_BRIDGE)).OTHER_BRIDGE();
        // ERC721 Bridge
        IERC721Bridge otherERC721Bridge = IERC721Bridge(payable(Predeploys.L2_ERC721_BRIDGE)).OTHER_BRIDGE();

        // 4. Upgrade the remaining proxies
        _upgradeProxies();

        // Assert the L1 messenger configs match the pre-isthmus values
        assertEq(
            address(otherMessenger),
            abi.decode(
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.L1_CROSS_DOMAIN_MESSENGER_ADDRESS),
                (address)
            )
        );

        // Assert the L1 standard bridge configs match the pre-isthmus values
        assertEq(
            address(otherStandardBridge),
            abi.decode(
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.L1_STANDARD_BRIDGE_ADDRESS),
                (address)
            )
        );

        // Assert the L1 ERC721 bridge configs match the pre-isthmus values
        assertEq(
            address(otherERC721Bridge),
            abi.decode(
                IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).getConfig(Types.ConfigType.L1_ERC_721_BRIDGE_ADDRESS),
                (address)
            )
        );
    }

    /// @dev This test is used to test a deposit transaction upgrade
    ///      This test assumes that a proper deposit transaction has already been sent, emitting the appropriate
    ///      TransactionDeposited event.
    function test_depositTransaction_upgrade() external {
        vm.skip(!isL2ForkTest());

        // 1. Deploy the new implementation contract in L2
        IL2CrossDomainMessenger newCrossDomainMessenger = IL2CrossDomainMessenger(
            DeployUtils.createDeterministic({ _name: "L2CrossDomainMessenger", _args: bytes(""), _salt: _salt })
        );

        // 2. Upgrade the L2CrossDomainMessenger contract
        vm.prank(IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN).owner());
        IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN).upgrade(
            payable(Predeploys.L2_CROSS_DOMAIN_MESSENGER), payable(address(newCrossDomainMessenger))
        );
    }

    /// @dev This function is used to upgrade the L1Block contract.
    function _upgradeL1Block() internal {
        IL1Block l1Block =
            IL1Block(DeployUtils.createDeterministic({ _name: "L1Block", _args: bytes(""), _salt: _salt }));

        IL2ProxyAdmin proxyAdmin = IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(payable(Predeploys.L1_BLOCK_ATTRIBUTES), address(l1Block));
    }

    /// @dev This function is used to upgrade the remaining proxies used in the isthmus upgrade flow.
    function _upgradeProxies() internal {
        IL2ProxyAdmin proxyAdmin = IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN);

        // Bridges
        address standardBridge =
            DeployUtils.createDeterministic({ _name: "L2StandardBridge", _args: bytes(""), _salt: _salt });
        address erc721Bridge =
            DeployUtils.createDeterministic({ _name: "L2ERC721Bridge", _args: bytes(""), _salt: _salt });

        // Fee Vaults
        address baseFeeVault =
            DeployUtils.createDeterministic({ _name: "BaseFeeVault", _args: bytes(""), _salt: _salt });
        address l1FeeVault = DeployUtils.createDeterministic({ _name: "L1FeeVault", _args: bytes(""), _salt: _salt });
        address sequencerFeeVault =
            DeployUtils.createDeterministic({ _name: "SequencerFeeVault", _args: bytes(""), _salt: _salt });

        vm.startPrank(proxyAdmin.owner());
        proxyAdmin.upgrade(payable(Predeploys.BASE_FEE_VAULT), address(baseFeeVault));
        proxyAdmin.upgrade(payable(Predeploys.L1_FEE_VAULT), address(l1FeeVault));
        proxyAdmin.upgrade(payable(Predeploys.SEQUENCER_FEE_WALLET), address(sequencerFeeVault));
        proxyAdmin.upgrade(payable(Predeploys.L2_STANDARD_BRIDGE), address(standardBridge));
        proxyAdmin.upgrade(payable(Predeploys.L2_ERC721_BRIDGE), address(erc721Bridge));
        vm.stopPrank();
    }

    /// @dev This function compares the fee vault config to the expected values.
    /// @param _config The fee vault config to compare.
    /// @param _recipient The expected recipient of the fee vault.
    /// @param _minWithdrawalAmount The expected minimum withdrawal amount of the fee vault.
    /// @return true if the fee vault config matches the expected values, false otherwise.
    function _checkFeeVaultConfig(
        bytes memory _config,
        address _recipient,
        uint256 _minWithdrawalAmount
    )
        internal
        pure
        returns (bool)
    {
        return abi.decode(_config, (bytes32))
            == Encoding.encodeFeeVaultConfig(_recipient, _minWithdrawalAmount, Types.WithdrawalNetwork.L2);
    }
}
