// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IL1CGTBridge } from "./IL1CGTBridge.sol";
import { Types } from "src/libraries/Types.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @title IL1CGTBridgeWithLegacyWithdrawal
/// @notice Interface for the L1CGTBridge contract with additional legacy withdrawal functionality.
///         This extension includes functionality for handling legacy withdrawals from before CGT
///         migration, bridge management controls, and trusted state management.
interface IL1CGTBridgeWithLegacyWithdrawal is IL1CGTBridge {
    /// @notice Thrown when trying to set trusted state more than once.
    error TrustedStateAlreadySet();

    /// @notice Thrown when trying to use legacy functions before setting trusted state.
    error TrustedStateNotSet();

    /// @notice Thrown when deposits are disabled.
    error DepositsDisabled();

    /// @notice Thrown when withdrawals are disabled.
    error WithdrawalsDisabled();

    /// @notice Thrown when withdrawal has already been finalized.
    error WithdrawalAlreadyFinalized();

    /// @notice Thrown when withdrawal has not been proven.
    error WithdrawalNotProven();

    /// @notice Thrown when trying to finalize a withdrawal with zero value.
    error InvalidWithdrawalValue();

    /// @notice Thrown when trusted root is zero.
    error InvalidTrustedRoot();
    /// @notice Emitted when a legacy withdrawal is proven.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param from           Address of the sender.
    /// @param to             Address of the receiver.

    event WithdrawalProven(bytes32 indexed withdrawalHash, address indexed from, address indexed to);

    /// @notice Emitted when a legacy withdrawal is proven (extension event).
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param proofSubmitter Address that submitted the proof.
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when a legacy withdrawal is finalized.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param success        Whether the withdrawal was successful.
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

    /// @notice Emitted when deposits are enabled or disabled.
    /// @param enabled Whether deposits are enabled.
    event DepositsToggled(bool enabled);

    /// @notice Emitted when withdrawals are enabled or disabled.
    /// @param enabled Whether withdrawals are enabled.
    event WithdrawalsToggled(bool enabled);

    /// @notice Emitted when the trusted state is set.
    /// @param trustedRoot The trusted L2ToL1MessagePasser storage root.
    event TrustedStateSet(bytes32 indexed trustedRoot);

    /// @notice Initializes the contract.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    /// @param _optimismPortal   Address of the OptimismPortal2 contract.
    function initialize(
        ICrossDomainMessenger _messenger,
        ISuperchainConfig _superchainConfig,
        IOptimismPortal2 _optimismPortal
    )
        external;

    /// @notice Sets the trusted L2ToL1MessagePasser storage root for legacy withdrawal verification.
    ///         This function can only be called once during migration.
    /// @param trustedRoot The trusted storage root to set.
    function setTrustedStateOnce(bytes32 trustedRoot) external;

    /// @notice Proves a legacy withdrawal transaction using the trusted storage root.
    /// @param _tx              The withdrawal transaction to prove.
    /// @param _withdrawalProof The proof of inclusion in the trusted storage root.
    function legacyProveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        bytes[] calldata _withdrawalProof
    )
        external;

    /// @notice Finalizes a proven legacy withdrawal transaction.
    /// @param _tx The withdrawal transaction to finalize.
    function legacyFinalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external;

    /// @notice Enables deposit functionality.
    function enableDeposits() external;

    /// @notice Disables deposit functionality.
    function disableDeposits() external;

    /// @notice Enables withdrawal functionality.
    function enableWithdrawals() external;

    /// @notice Disables withdrawal functionality.
    function disableWithdrawals() external;

    /// @notice Returns the trusted L2ToL1MessagePasser storage root.
    /// @return The trusted storage root, or zero if not set.
    function trustedMessagePasserStorageRoot() external view returns (bytes32);

    /// @notice Returns whether deposits are currently enabled.
    /// @return True if deposits are enabled, false otherwise.
    function depositsEnabled() external view returns (bool);

    /// @notice Returns whether withdrawals are currently enabled.
    /// @return True if withdrawals are enabled, false otherwise.
    function withdrawalsEnabled() external view returns (bool);

    /// @notice Returns the address of the OptimismPortal2 contract.
    /// @return Address of the OptimismPortal2 contract.
    function optimismPortal() external view returns (IOptimismPortal2);
}
