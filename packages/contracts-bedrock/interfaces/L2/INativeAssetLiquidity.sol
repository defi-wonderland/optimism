// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INativeAssetLiquidity {
    error Unauthorized();

    event LiquidityDeposited(address indexed caller, uint256 value);
    event LiquidityWithdrawn(address indexed caller, uint256 value);

    function deposit() external payable;
    function withdraw(uint256 _amount) external;
}
