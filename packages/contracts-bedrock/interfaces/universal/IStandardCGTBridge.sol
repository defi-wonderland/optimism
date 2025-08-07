// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

interface IStandardCGTBridge {
    /// @notice Emitted when a CGT bridge is initiated on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when a CGT bridge is finalized on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Address of the CGT token.
    function cgtToken() external view returns (address);

    /// @notice Messenger contract on this domain.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Corresponding bridge on the other domain.
    function otherBridge() external view returns (IStandardCGTBridge);

    /// @notice Returns the paused state of the bridge.
    /// @return True if the bridge is paused, false otherwise.
    function paused() external view returns (bool);

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeCGT(
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external;

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeCGTTo(
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external;

    /// @notice Finalizes an ERC20 bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeCGT(
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external;
}
