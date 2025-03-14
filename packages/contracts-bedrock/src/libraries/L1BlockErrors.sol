// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Error returns when a non-depositor account tries to set L1 block values.
error NotDepositor();

/// @notice Error when a non-cross L2 Inbox sender tries to call the `isDeposit()` method.
error NotCrossL2Inbox();

// TODO: This name will change based on the fork name the l2genesis changes will land on.
/// @notice Error when the L1Block is already an XFork upgraded chain.
error XForkAlreadyActive();
