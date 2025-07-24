// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";
import { SafeSend } from "src/universal/SafeSend.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000030
/// @title NativeAssetLiquidity
/// @notice The NativeAssetLiquidity contract allows other contracts to access native asset liquidity
contract NativeAssetLiquidity {
    /// @notice Emitted when an address withdraws native asset liquidity.
    event LiquidityWithdrawn(address indexed caller, uint256 value);

    /// @notice Emitted when an address deposits native asset liquidity.
    event LiquidityDeposited(address indexed caller, uint256 value);

    /// @notice Allows an address to lock native asset liquidity into this contract.
    function deposit() external payable {
        if (msg.sender != Predeploys.LIQUIDITY_CONTROLLER) revert Unauthorized();
        emit LiquidityDeposited(msg.sender, msg.value);
    }

    /// @notice Allows an address to unlock native asset liquidity from this contract.
    /// @param _amount The amount of liquidity to unlock.
    function withdraw(uint256 _amount) external {
        if (msg.sender != Predeploys.LIQUIDITY_CONTROLLER) revert Unauthorized();
        new SafeSend{ value: _amount }(payable(msg.sender));
        emit LiquidityWithdrawn(msg.sender, _amount);
    }
}
