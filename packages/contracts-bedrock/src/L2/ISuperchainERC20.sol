// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title ISuperchainERC20
/// @notice This interface is available on the SuperchainERC20 contract.
///         We declare it as a separate interface so that it can be used in
///         custom implementations of SuperchainERC20.
interface ISuperchainERC20 {
    /// @notice Address of the StandardBridge on this network.
    function bridge() external view returns (address);

    /// @notice Allows the StandardBridge on this network to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(address _to, uint256 _amount) external;

    /// @notice Allows the StandardBridge on this network to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(address _from, uint256 _amount) external;

    /// @notice Sends tokens to some target address on another chain.
    /// @param _to      Address to send tokens to.
    /// @param _amount  Amount of tokens to send.
    /// @param _chainId Chain ID of the destination chain.
    /// @param _data    Data to be sent with the message.
    function sendERC20(address _to, uint256 _amount, uint256 _chainId, bytes memory _data) external;

    /// @notice Relays tokens received from another chain.
    /// @param _to     Address to relay tokens to.
    /// @param _amount Amount of tokens to relay.
    /// @param _data   Data sent with the message.
    function relayERC20(address _to, uint256 _amount, bytes memory _data) external;
}
