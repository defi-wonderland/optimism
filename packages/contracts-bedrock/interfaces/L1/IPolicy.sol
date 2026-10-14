// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

/// @title IPolicy
/// @notice Decides what the ComplianceModule accepts. Verdicts reach the module only through the
///         policy, which calls `recordVerdict` and `revokeVerdict` on it.
interface IPolicy {
    /// @notice Screens a deposit at submission. A revert rejects it.
    /// @param _item    The deposit.
    /// @param _parties Parties resolved by the module, initiator first.
    /// @return pass_ True to proceed, false to hold.
    function screen(Item calldata _item, address[] calldata _parties) external returns (bool pass_);

    /// @notice Screens an item when its value moves: a withdrawal at finalization, or a held item
    ///         at completion. For a withdrawal, false holds it and a revert leaves it finalizable,
    ///         so a policy that wants to wait reverts. A policy must also revert, never return
    ///         false, when something it calls fails, since whoever finalizes chooses the gas.
    /// @param _item          The item.
    /// @param _parties       Parties resolved by the module, initiator first.
    /// @param _clearedAt     When a clear verdict was recorded for the item, zero if none.
    /// @param _finalizableAt When a withdrawal being finalized became finalizable, zero at completion.
    /// @return pass_ True to let the value move.
    function screenRelease(
        Item calldata _item,
        address[] calldata _parties,
        uint64 _clearedAt,
        uint256 _finalizableAt
    )
        external
        returns (bool pass_);
}
