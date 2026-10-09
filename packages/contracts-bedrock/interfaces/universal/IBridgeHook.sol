// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

/// @title IBridgeHook
/// @notice Contract the OptimismPortal asks about every deposit and withdrawal when it is set as
///         the Portal's bridge hook.
interface IBridgeHook {
    /// @notice Screens a deposit. A revert rejects it.
    /// @param _item The deposit.
    /// @return pass_ True to proceed, false to hold.
    function screenDeposit(Item calldata _item) external returns (bool pass_);

    /// @notice Takes custody of a held deposit. ETH comes with the call. Escrowed tokens are
    ///         transferred by the L1StandardBridge just before it.
    /// @param _item The held deposit.
    function holdDeposit(Item calldata _item) external payable;

    /// @notice Screens a withdrawal at finalization. A revert rejects it for now: nothing is
    ///         consumed and it can be finalized again, so a hook that wants to wait reverts.
    /// @param _item          The withdrawal.
    /// @param _finalizableAt When the withdrawal became finalizable, with the proof being used.
    /// @return pass_ True to pay it, false to hold it.
    function screenWithdrawal(Item calldata _item, uint256 _finalizableAt) external returns (bool pass_);

    /// @notice Takes custody of a held withdrawal. ETH comes with the call. Escrowed tokens are
    ///         transferred by the L1StandardBridge just before it.
    /// @param _item The held withdrawal.
    function holdWithdrawal(Item calldata _item) external payable;
}
