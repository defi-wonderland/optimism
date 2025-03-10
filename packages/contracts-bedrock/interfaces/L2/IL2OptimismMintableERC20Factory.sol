// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IL2OptimismMintableERC20Factory {
    event OptimismMintableERC20Created(address indexed localToken, address indexed remoteToken, address deployer);
    event StandardL2TokenCreated(address indexed remoteToken, address indexed localToken);

    function BRIDGE() external view returns (address bridge_);
    function bridge() external view returns (address bridge_);
    function createOptimismMintableERC20(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address newTokenAddress_);
    function createOptimismMintableERC20WithDecimals(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
        returns (address newTokenAddress_);
    function createStandardL2Token(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address newTokenAddress_);
    function deployments(address _localToken) external view returns (address remoteToken_);
    function version() external view returns (string memory version_);

    function __constructor__() external;
}
