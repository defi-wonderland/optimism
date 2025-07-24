// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityController {
    function authorizeMinter(address _minter) external;
    function mint(address _to, uint256 _amount) external;
    function burn() external payable;
    function gasPayingTokenName() external view returns (string memory);
    function gasPayingTokenSymbol() external view returns (string memory);
    function gasPayingTokenDecimals() external view returns (uint8);
}
