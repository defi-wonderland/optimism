// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

/// @title IBridgeHook
/// @notice The one seam the BRIDGE_HOOK feature adds to the protocol. Four functions serve four
///         call sites, because the asset class is data rather than a signature: the ETH and
///         ERC-20 paths differ in what the call site fills into `Item` and in nothing else.
/// @dev Three outcomes and no enum. `true` proceeds, `false` holds, a revert rejects and unwinds
///      the transaction. That is what lets one interface serve an asynchronous policy, which
///      always holds, and a synchronous one such as a rate limiter, which passes or reverts over
///      the cap.
///
///      Deciding and taking custody are two calls in both directions, and no value moves on the
///      deciding one. A hook that never keeps anything therefore never receives anything, and
///      need not be payable at all beyond the handover it declines to use. The alternative,
///      handing the value over with the question and taking it back on a pass, makes custody a
///      property of the interface rather than a choice of the hook, and obliges the call site to
///      verify that the value came back.
interface IBridgeHook {
    /// @notice Called by whichever contract has the value, before it commits anything and before
    ///         any value moves.
    /// @param _item The item entering.
    /// @return pass_ True to proceed, false to hold. A revert rejects the item.
    function screenDeposit(Item calldata _item) external returns (bool pass_);

    /// @notice Custody handover for a held deposit, called after `screenDeposit` returns false and
    ///         after the call site has committed to the item's terms. The caller sends the ETH
    ///         with the call, or transfers the tokens immediately before it.
    /// @param _item The item being handed over.
    function holdDeposit(Item calldata _item) external payable;

    /// @notice Called immediately before value would be released on L1.
    /// @dev A revert here is a fault rather than a decision: there is nothing to unwind, so it
    ///      halts finalization for everyone.
    /// @param _item The item leaving.
    /// @return pass_ True to release to the recipient, false to route into holding.
    function screenWithdrawal(Item calldata _item) external returns (bool pass_);

    /// @notice Custody handover for a held withdrawal, called after `screenWithdrawal` returns
    ///         false. The caller sends ETH with the call, or transfers the tokens immediately
    ///         before it.
    /// @param _item The item being handed over.
    function holdWithdrawal(Item calldata _item) external payable;
}
