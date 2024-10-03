// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICrosschainERC20
/// @notice This interface is a standard for crosschain ERC20 transfers.
interface ICrosschainERC20 {
    /// @notice Emitted whenever tokens are minted by a crosschain transfer.
    /// @param account Address of the account tokens are being minted for.
    /// @param amount  Amount of tokens minted.
    event CrosschainMinted(address indexed account, uint256 amount);

    /// @notice Emitted whenever tokens are burned by a crosschain transfer.
    /// @param account Address of the account tokens are being burned from.
    /// @param amount  Amount of tokens burned.
    event CrosschainBurnt(address indexed account, uint256 amount);

    /// @notice Allows to mint tokens through a crosschain transfer.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function __crosschainMint(address _to, uint256 _amount) external;

    /// @notice Allows to burn tokens through a crosschain transfer.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function __crosschainBurn(address _from, uint256 _amount) external;
}
