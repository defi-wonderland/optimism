// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IXForkL2ContractsManager } from "interfaces/L2/IXForkL2ContractsManager.sol";

// Libraries
import { Constants } from "src/libraries/Constants.sol";

// Contracts
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

/// @title L2ProxyAdmin
contract L2ProxyAdmin is ProxyAdmin {
    /// @notice Thrown when the caller is not the owner or the depositor account.
    error L2ProxyAdmin__InvalidCaller();

    /// @notice Thrown when the upgrade fails.
    error L2ProxyAdmin__UpgradeFailed(bytes data);

    /// @param _owner Address of the initial owner of this contract.
    constructor(address _owner) ProxyAdmin(_owner) { }

    /// @notice Upgrades the predeploys via delegatecall to the xForkL2ContractsManager contract.
    /// @param xForkL2ContractsManager Address of the xForkL2ContractsManager contract.
    function upgradePredeploys(address xForkL2ContractsManager) external {
        if (msg.sender != owner() && msg.sender != Constants.DEPOSITOR_ACCOUNT) revert L2ProxyAdmin__InvalidCaller();

        (bool success, bytes memory data) =
            xForkL2ContractsManager.delegatecall(abi.encodeCall(IXForkL2ContractsManager.upgrade, ()));

        if (!success) revert L2ProxyAdmin__UpgradeFailed(data);
    }
}
