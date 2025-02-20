// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Interfaces
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title IERC7802Adapter
/// @notice This interface is available on the ERC7802Adapter contract.
interface IERC7802Adapter is IERC7802, ISemver {}
