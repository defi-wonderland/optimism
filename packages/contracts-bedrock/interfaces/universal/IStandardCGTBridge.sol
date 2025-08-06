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
    function paused() public view virtual returns (bool);

    /// @notice Initializes the bridge contract.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        address _otherBridge
    ) external;


    /// @notice Finalizes a CGT bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external;
}
