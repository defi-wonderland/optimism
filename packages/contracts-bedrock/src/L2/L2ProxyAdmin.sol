// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Constants } from "src/libraries/Constants.sol";
import { NUTExecutor } from "src/L2/NUTExecutor.sol";

/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L2ProxyAdmin
/// @notice This contract is the admin for the L2 proxy contracts.
contract L2ProxyAdmin is ProxyAdmin {
    constructor(address _owner) ProxyAdmin(_owner) { }

    /// @dev allow Constants.DEPOSITOR_ACCOUNT to perform delegated calls
    function _checkOwner() internal view override {
        require(
            owner() == _msgSender() || Constants.DEPOSITOR_ACCOUNT == _msgSender(), "Ownable: caller is not the owner"
        );
    }

    function performDelegateCall(address _target) external payable onlyOwner {
        (bool success,) = _target.delegatecall(abi.encodeCall(NUTExecutor.execute, ()));
        require(success, "ProxyAdmin: delegatecall to target failed");
    }
}
