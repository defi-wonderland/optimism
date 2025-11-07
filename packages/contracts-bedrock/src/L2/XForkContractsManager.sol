// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";

/// @title XForkContractsManager
/// @notice The XForkContractsManager is responsible for orquestrating the upgrades of the L2 contracts during xFork
/// hardforks.
contract XForkContractsManager is L2ContractsManager {
    /// @notice Hook called before execution.
    function _beforeExecution() internal override { }

    /// @notice Hook called after execution.
    function _afterExecution(bytes memory returnData) internal override { }
}
