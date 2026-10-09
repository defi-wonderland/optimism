// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

/// @title IPolicy
/// @notice The only compliance address the module knows. Everything that decides *what* is
///         acceptable and *who* may say so lives behind these two functions: the registered rules
///         and their precedence, the on-chain allow and deny lists, any synchronous source, the
///         freshness bound, the emergency disable, the officer role, and which addresses may cause
///         a verdict. All of it changes at runtime with no redeploy, chain upgrade or migration of
///         held value, and the module is untouched by every one of those changes because it never
///         learns they exist.
/// @dev Two functions, because the call sites ask different questions. At submission it is "may
///      this enter". At the value-moving step it is "may this leave, given it was cleared at time
///      T", which needs the clearance timestamp. That timestamp cannot travel inside `Item`,
///      because `Item` is the preimage of the identifier and nothing mutable may go in it.
///
///      A policy is also expected to write verdicts back to the module through
///      `recordVerdict` and `revokeVerdict`, having checked its own authority first. The module's
///      whole authorisation surface for verdicts is `msg.sender == policy`.
interface IPolicy {
    /// @notice Screens an item at submission.
    /// @param _item    The item.
    /// @param _parties The effective parties, resolved by the module.
    /// @return pass_ True to pass, false to hold. A revert rejects the item.
    function screen(Item calldata _item, address[] calldata _parties) external returns (bool pass_);

    /// @notice Screens an item at the moment value moves. This is where the live deny read, the
    ///         freshness bound and any direction-specific rule apply.
    /// @param _item      The item.
    /// @param _parties   The effective parties, resolved by the module.
    /// @param _clearedAt When a clear verdict was recorded for this item, or zero if none. A
    ///                   policy seeing zero at a withdrawal call site declines, which routes the
    ///                   withdrawal into holding.
    /// @return pass_ True to let the value move.
    function screenRelease(
        Item calldata _item,
        address[] calldata _parties,
        uint64 _clearedAt
    )
        external
        returns (bool pass_);
}
