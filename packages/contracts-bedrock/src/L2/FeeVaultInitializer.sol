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
/// @notice This contract deploys new fee vault implementations with current configurations as immutables.
contract FeeVaultInitializer is ISemver {

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Emitted when the Base Fee Vault is deployed.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The deployed implementation address.
    /// @param recipient The recipient address for the implementation.
    /// @param network The withdrawal network for the implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the implementation.
    event BaseFeeVaultDeployed(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the Sequencer Fee Vault is deployed.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The deployed implementation address.
    /// @param recipient The recipient address for the implementation.
    /// @param network The withdrawal network for the implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the implementation.
    event SequencerFeeVaultDeployed(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the L1 Fee Vault is deployed.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The deployed implementation address.
    /// @param recipient The recipient address for the implementation.
    /// @param network The withdrawal network for the implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the implementation.
    event L1FeeVaultDeployed(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Emitted when the Operator Fee Vault is deployed.
    /// @param oldImplementation The previous implementation address.
    /// @param newImplementation The deployed implementation address.
    /// @param recipient The recipient address for the implementation.
    /// @param network The withdrawal network for the implementation.
    /// @param minWithdrawalAmount The minimum withdrawal amount for the implementation.
    event OperatorFeeVaultDeployed(
        address indexed oldImplementation,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    /// @notice Constructor that deploys new fee vault implementations with current values as immutables.
    constructor() {
        _deployBaseFeeVault();
        _deploySequencerFeeVault();
        _deployL1FeeVault();
        _deployOperatorFeeVault();
    }

    function _deployBaseFeeVault() internal {
        // Get current values from the existing fee vault
        address recipient;
        Types.WithdrawalNetwork network;
        uint256 minWithdrawalAmount;
        address currentImplementation = IProxy(payable(Predeploys.BASE_FEE_VAULT)).implementation();

        // Try to get values using new camelCase functions, fallback to legacy snake_case if it fails
        try FeeVault(payable(Predeploys.BASE_FEE_VAULT)).recipient() returns (address _recipient) {
            recipient = _recipient;
        } catch {
            // Legacy implementation - try snake_case function
            recipient = FeeVault(payable(Predeploys.BASE_FEE_VAULT)).RECIPIENT();
        }

        try FeeVault(payable(Predeploys.BASE_FEE_VAULT)).withdrawalNetwork() returns (Types.WithdrawalNetwork _network) {
            network = _network;
        } catch {
            // Legacy implementation - try snake_case function
            network = FeeVault(payable(Predeploys.BASE_FEE_VAULT)).WITHDRAWAL_NETWORK();
        }

        try FeeVault(payable(Predeploys.BASE_FEE_VAULT)).minWithdrawalAmount() returns (uint256 _minWithdrawalAmount) {
            minWithdrawalAmount = _minWithdrawalAmount;
        } catch {
            // Legacy implementation - try snake_case function
            minWithdrawalAmount = FeeVault(payable(Predeploys.BASE_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();
        }

        // Deploy new implementation with current values as immutables
        BaseFeeVault newBaseFeeVault = new BaseFeeVault(recipient, minWithdrawalAmount, network);

        emit BaseFeeVaultDeployed(
            currentImplementation,
            address(newBaseFeeVault),
            recipient,
            network,
            minWithdrawalAmount
        );
    }

    function _deploySequencerFeeVault() internal {
        // Get current values from the existing fee vault
        address recipient;
        Types.WithdrawalNetwork network;
        uint256 minWithdrawalAmount;
        address currentImplementation = IProxy(payable(Predeploys.SEQUENCER_FEE_WALLET)).implementation();

        // Try to get values using new camelCase functions, fallback to legacy snake_case if it fails
        try FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).recipient() returns (address _recipient) {
            recipient = _recipient;
        } catch {
            // Legacy implementation - try snake_case function
            recipient = FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).RECIPIENT();
        }

        try FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).withdrawalNetwork() returns (Types.WithdrawalNetwork _network) {
            network = _network;
        } catch {
            // Legacy implementation - try snake_case function
            network = FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).WITHDRAWAL_NETWORK();
        }

        try FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).minWithdrawalAmount() returns (uint256 _minWithdrawalAmount) {
            minWithdrawalAmount = _minWithdrawalAmount;
        } catch {
            // Legacy implementation - try snake_case function
            minWithdrawalAmount = FeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).MIN_WITHDRAWAL_AMOUNT();
        }

        // Deploy new implementation with current values as immutables
        SequencerFeeVault newSequencerFeeVault = new SequencerFeeVault(recipient, minWithdrawalAmount, network);

        emit SequencerFeeVaultDeployed(
            currentImplementation,
            address(newSequencerFeeVault),
            recipient,
            network,
            minWithdrawalAmount
        );
    }

    function _deployL1FeeVault() internal {
        // Get current values from the existing fee vault
        address recipient;
        Types.WithdrawalNetwork network;
        uint256 minWithdrawalAmount;
        address currentImplementation = IProxy(payable(Predeploys.L1_FEE_VAULT)).implementation();

        // Try to get values using new camelCase functions, fallback to legacy snake_case if it fails
        try FeeVault(payable(Predeploys.L1_FEE_VAULT)).recipient() returns (address _recipient) {
            recipient = _recipient;
        } catch {
            // Legacy implementation - try snake_case function
            recipient = FeeVault(payable(Predeploys.L1_FEE_VAULT)).RECIPIENT();
        }

        try FeeVault(payable(Predeploys.L1_FEE_VAULT)).withdrawalNetwork() returns (Types.WithdrawalNetwork _network) {
            network = _network;
        } catch {
            // Legacy implementation - try snake_case function
            network = FeeVault(payable(Predeploys.L1_FEE_VAULT)).WITHDRAWAL_NETWORK();
        }

        try FeeVault(payable(Predeploys.L1_FEE_VAULT)).minWithdrawalAmount() returns (uint256 _minWithdrawalAmount) {
            minWithdrawalAmount = _minWithdrawalAmount;
        } catch {
            // Legacy implementation - try snake_case function
            minWithdrawalAmount = FeeVault(payable(Predeploys.L1_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();
        }

        // Deploy new implementation with current values as immutables
        L1FeeVault newL1FeeVault = new L1FeeVault(recipient, minWithdrawalAmount, network);

        emit L1FeeVaultDeployed(
            currentImplementation,
            address(newL1FeeVault),
            recipient,
            network,
            minWithdrawalAmount
        );
    }

    function _deployOperatorFeeVault() internal {
        // Get current values from the existing fee vault
        address recipient;
        Types.WithdrawalNetwork network;
        uint256 minWithdrawalAmount;
        address currentImplementation = IProxy(payable(Predeploys.OPERATOR_FEE_VAULT)).implementation();

        // Try to get values using new camelCase functions, fallback to legacy snake_case if it fails
        try FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).recipient() returns (address _recipient) {
            recipient = _recipient;
        } catch {
            // Legacy implementation - try snake_case function
            recipient = FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).RECIPIENT();
        }

        try FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).withdrawalNetwork() returns (Types.WithdrawalNetwork _network) {
            network = _network;
        } catch {
            // Legacy implementation - try snake_case function
            network = FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).WITHDRAWAL_NETWORK();
        }

        try FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).minWithdrawalAmount() returns (uint256 _minWithdrawalAmount) {
            minWithdrawalAmount = _minWithdrawalAmount;
        } catch {
            // Legacy implementation - try snake_case function
            minWithdrawalAmount = FeeVault(payable(Predeploys.OPERATOR_FEE_VAULT)).MIN_WITHDRAWAL_AMOUNT();
        }

        // Deploy new implementation with current values as immutables
        OperatorFeeVault newOperatorFeeVault = new OperatorFeeVault(recipient, minWithdrawalAmount, network);

        emit OperatorFeeVaultDeployed(
            currentImplementation,
            address(newOperatorFeeVault),
            recipient,
            network,
            minWithdrawalAmount
        );
    }
}
