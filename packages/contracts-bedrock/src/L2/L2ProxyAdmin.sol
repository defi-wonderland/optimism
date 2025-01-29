// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @notice Thrown when the owner is attempted to be transferred.
error OwnerCannotBeTransferred();

/// @notice Thrown when the owner is attempted to be renounced.
error OwnershipCannotBeRenounced();

/// @custom:proxied true
/// @custom:predeploy
/// @title L2ProxyAdmin
contract L2ProxyAdmin is ProxyAdmin {
    /// @notice The constructor initializes the ProxyAdmin with the `DEPOSITOR_ACCOUNT` as the owner.
    constructor() ProxyAdmin(Constants.DEPOSITOR_ACCOUNT) { }

    /// @notice The owner of the L2ProxyAdmin is the `DEPOSITOR_ACCOUNT`.
    function owner() public view override returns (address) {
        return Constants.DEPOSITOR_ACCOUNT;
    }

    /// @notice The owner of the L2ProxyAdmin cannot be transferred.
    function transferOwnership(address) public pure override {
        revert OwnerCannotBeTransferred();
    }

    /// @notice The owner of the L2ProxyAdmin cannot be renounced.
    function renounceOwnership() public pure override {
        revert OwnershipCannotBeRenounced();
    }
}
