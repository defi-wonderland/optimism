// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @notice Base contract for L2 Contracts Manager, responsible for orquestrating the upgrades
///         of the L2 contracts during hardforks.
abstract contract L2ContractsManager {
    /// @notice Executes the NUT with before/after hooks.
    /// @param data Data to be passed to the execution.
    /// @return Return data from the execution.
    function execute(bytes memory data) external returns (bytes memory) {
        _beforeExecution();
        bytes memory returnData = _performExecute(data);
        _afterExecution(returnData);
        return returnData;
    }

    /// @notice Hook called before execution.
    function _beforeExecution() internal virtual;

    /// @notice Hook called after execution.
    /// @param returnData Data returned from execution.
    function _afterExecution(bytes memory returnData) internal virtual;

    /// @notice Performs the actual execution logic.
    /// @return Return data from the execution.
    function _performExecute(bytes memory data) internal virtual returns (bytes memory) { }
}
