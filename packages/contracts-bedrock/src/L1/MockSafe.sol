// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @title MockSafe
/// @notice Simple contract that simulates a Safe by executing delegatecalls.
///         Used for testing the FaucetDeployer flow.
contract MockSafe {
    /// @notice Executes a delegatecall to a target contract
    /// @param _target The contract to delegatecall
    /// @param _data The calldata to send
    /// @return success Whether the call succeeded
    /// @return returnData The return data from the call
    function executeDelegateCall(address _target, bytes calldata _data) external returns (bool success, bytes memory returnData) {
        (success, returnData) = _target.delegatecall(_data);
        require(success, "MockSafe: delegatecall failed");
    }
}
