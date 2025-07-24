// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityController {
    error Unauthorized();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function authorizeMinter(address _minter) external;
    function mint(address _to, uint256 _amount) external;
    function burn() external payable;
    function minters(address) external view returns (bool);
    function gasPayingTokenName() external view returns (string memory);
    function gasPayingTokenSymbol() external view returns (string memory);
    function gasPayingTokenDecimals() external view returns (uint8);

    function owner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;

    function __constructor__(string memory _gasPayingTokenName, string memory _gasPayingTokenSymbol) external;
}
