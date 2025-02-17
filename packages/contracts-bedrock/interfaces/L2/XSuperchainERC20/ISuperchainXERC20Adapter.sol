// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Interfaces
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title ISuperchainXERC20Adapter
/// @notice This interface is available on the SuperchainXERC20Adapter contract.
interface ISuperchainXERC20Adapter is IERC7802, ISemver {}
