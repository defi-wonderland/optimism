// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOptimismMintableERC721Factory {
    event OptimismMintableERC721Created(address indexed localToken, address indexed remoteToken, address deployer);

    function BRIDGE() external pure returns (address bridge_);
    function REMOTE_CHAIN_ID() external view returns (uint256 remoteChainID_);
    function bridge() external pure returns (address bridge_);
    function remoteChainID() external view returns (uint256 remoteChainID_);
    function createOptimismMintableERC721(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address newTokenAddress_);
    function isOptimismMintableERC721(address _token) external view returns (bool isOptimismMintableERC721_);
    function version() external view returns (string memory version_);

    function __constructor__() external;
}
