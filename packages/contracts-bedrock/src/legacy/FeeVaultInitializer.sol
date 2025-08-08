// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { FeeVault } from "src/L2/FeeVault.sol";
import { BaseFeeVault } from "src/L2/BaseFeeVault.sol";
import { SequencerFeeVault } from "src/L2/SequencerFeeVault.sol";
import { L1FeeVault } from "src/L2/L1FeeVault.sol";
import { OperatorFeeVault } from "src/L2/OperatorFeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";

/// @title FeeVaultInitializer
/// @notice This contract migrates the fee vaults from the legacy system to the new system.
contract FeeVaultInitializer is ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Constructs the FeeVaultMigrator contract.
    constructor() { }

    function migrate() public {
        _migrateBaseFeeVault();
        _migrateSequencerFeeVault();
        _migrateL1FeeVault();
        _migrateOperatorFeeVault();
    }

    function _migrateBaseFeeVault() internal {
        // Grab current values from the old fee vault
        address currentBaseFeeVaultRecipient = FeeVault(payable(Predeploys.BASE_FEE_VAULT)).recipient();
        Types.WithdrawalNetwork currentBaseFeeVaultWithdrawalNetwork =
            FeeVault(payable(Predeploys.BASE_FEE_VAULT)).withdrawalNetwork();
        uint256 currentBaseFeeVaultMinWithdrawalAmount =
            FeeVault(payable(Predeploys.BASE_FEE_VAULT)).minWithdrawalAmount();

        // Withdraw funds from the old fee vaults
        FeeVault(payable(Predeploys.BASE_FEE_VAULT)).withdraw();

        // Deploy new implementation
        BaseFeeVault newBaseFeeVault = new BaseFeeVault();

        // Upgrade the proxy and initialize the new implementation
        IProxy(payable(Predeploys.BASE_FEE_VAULT)).upgradeToAndCall(
            address(newBaseFeeVault),
            abi.encodeWithSelector(
                BaseFeeVault.initialize.selector,
                currentBaseFeeVaultRecipient,
                currentBaseFeeVaultMinWithdrawalAmount,
                currentBaseFeeVaultWithdrawalNetwork
            )
        );
    }

    function _migrateSequencerFeeVault() internal {
        // Grab current values from the old fee vault
        address currentSequencerFeeVaultRecipient = FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).recipient();
        Types.WithdrawalNetwork currentSequencerFeeVaultWithdrawalNetwork =
            FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).withdrawalNetwork();
        uint256 currentSequencerFeeVaultMinWithdrawalAmount =
            FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).minWithdrawalAmount();

        // Withdraw funds from the old fee vaults
        FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).withdraw();

        // Deploy new implementation
        SequencerFeeVault newSequencerFeeVault = new SequencerFeeVault();

        // Upgrade the proxy and initialize the new implementation
        IProxy(payable(Predeploys.SEQUENCER_FEE_WALLET)).upgradeToAndCall(
            address(newSequencerFeeVault),
            abi.encodeWithSelector(
                SequencerFeeVault.initialize.selector,
                currentSequencerFeeVaultRecipient,
                currentSequencerFeeVaultMinWithdrawalAmount,
                currentSequencerFeeVaultWithdrawalNetwork
            )
        );
    }

    function _migrateL1FeeVault() internal {
        // Grab current values from the old fee vault
        address currentL1FeeVaultRecipient = FeeVault(payable(Predeploys.L1_FEE_VAULT)).recipient();
        Types.WithdrawalNetwork currentL1FeeVaultWithdrawalNetwork =
            FeeVault(payable(Predeploys.L1_FEE_VAULT)).withdrawalNetwork();
        uint256 currentL1FeeVaultMinWithdrawalAmount = FeeVault(payable(Predeploys.L1_FEE_VAULT)).minWithdrawalAmount();

        // Withdraw funds from the old fee vaults
        FeeVault(payable(Predeploys.L1_FEE_VAULT)).withdraw();

        // Deploy new implementation
        L1FeeVault newL1FeeVault = new L1FeeVault();

        // Upgrade the proxy and initialize the new implementation
        IProxy(payable(Predeploys.L1_FEE_VAULT)).upgradeToAndCall(
            address(newL1FeeVault),
            abi.encodeWithSelector(
                L1FeeVault.initialize.selector,
                currentL1FeeVaultRecipient,
                currentL1FeeVaultMinWithdrawalAmount,
                currentL1FeeVaultWithdrawalNetwork
            )
        );
    }

    function _migrateOperatorFeeVault() internal {
        // Withdraw funds from the old fee vaults
        FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).withdraw();

        // Deploy new implementation Note this has hardcoded parameters in the constructor that initialize the feevault
        OperatorFeeVault newOperatorFeeVault = new OperatorFeeVault();

        // Upgrade the proxy and initialize the new implementation
        IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).upgradeToAndCall(
            address(newOperatorFeeVault), abi.encodeWithSelector(OperatorFeeVault.initialize.selector)
        );
    }
}
