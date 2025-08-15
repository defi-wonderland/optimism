// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

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

    /// @notice Emitted when the Sequencer Fee Vault is migrated.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The new implementation address.
    /// @param recipient The recipient address for the new implementation.
    /// @param network The withdrawal network for the new implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the new implementation.
    event SequencerFeeVaultUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the L1 Fee Vault is migrated.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The new implementation address.
    /// @param recipient The recipient address for the new implementation.
    /// @param network The withdrawal network for the new implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the new implementation.
    event L1FeeVaultUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the Base Fee Vault is migrated.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The new implementation address.
    /// @param recipient The recipient address for the new implementation.
    /// @param network The withdrawal network for the new implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the new implementation.
    event BaseFeeVaultUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the Operator Fee Vault is migrated.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The new implementation address.
    /// @param recipient The recipient address for the new implementation.
    /// @param network The withdrawal network for the new implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the new implementation.
    event OperatorFeeVaultUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Migrates all fee vaults to their new implementations.
    function migrate() external {
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
        address currentImplementation = IProxy(payable(Predeploys.BASE_FEE_VAULT)).implementation();

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

        emit BaseFeeVaultUpgraded(
            currentImplementation,
            address(newBaseFeeVault),
            currentBaseFeeVaultRecipient,
            currentBaseFeeVaultWithdrawalNetwork,
            currentBaseFeeVaultMinWithdrawalAmount
        );
    }

    function _migrateSequencerFeeVault() internal {
        // Grab current values from the old fee vault
        address currentSequencerFeeVaultRecipient = FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).recipient();
        Types.WithdrawalNetwork currentSequencerFeeVaultWithdrawalNetwork =
            FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).withdrawalNetwork();
        uint256 currentSequencerFeeVaultMinWithdrawalAmount =
            FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).minWithdrawalAmount();
        address currentImplementation = IProxy(payable(Predeploys.SEQUENCER_FEE_WALLET)).implementation();

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

        emit SequencerFeeVaultUpgraded(
            currentImplementation,
            address(newSequencerFeeVault),
            currentSequencerFeeVaultRecipient,
            currentSequencerFeeVaultWithdrawalNetwork,
            currentSequencerFeeVaultMinWithdrawalAmount
        );
    }

    function _migrateL1FeeVault() internal {
        // Grab current values from the old fee vault
        address currentL1FeeVaultRecipient = FeeVault(payable(Predeploys.L1_FEE_VAULT)).recipient();
        Types.WithdrawalNetwork currentL1FeeVaultWithdrawalNetwork =
            FeeVault(payable(Predeploys.L1_FEE_VAULT)).withdrawalNetwork();
        uint256 currentL1FeeVaultMinWithdrawalAmount = FeeVault(payable(Predeploys.L1_FEE_VAULT)).minWithdrawalAmount();
        address currentImplementation = IProxy(payable(Predeploys.L1_FEE_VAULT)).implementation();

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

        emit L1FeeVaultUpgraded(
            currentImplementation,
            address(newL1FeeVault),
            currentL1FeeVaultRecipient,
            currentL1FeeVaultWithdrawalNetwork,
            currentL1FeeVaultMinWithdrawalAmount
        );
    }

    function _migrateOperatorFeeVault() internal {
        // Grab current implementation for the event
        address currentImplementation = IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).implementation();

        // Deploy new implementation Note this has hardcoded parameters in the constructor that initialize the feevault
        OperatorFeeVault newOperatorFeeVault = new OperatorFeeVault();

        // Upgrade the proxy and initialize the new implementation
        IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).upgradeToAndCall(
            address(newOperatorFeeVault), abi.encodeWithSelector(OperatorFeeVault.initialize.selector)
        );

        emit OperatorFeeVaultUpgraded(
            currentImplementation,
            address(newOperatorFeeVault),
            newOperatorFeeVault.recipient(),
            newOperatorFeeVault.withdrawalNetwork(),
            newOperatorFeeVault.minWithdrawalAmount()
        );
    }
}
