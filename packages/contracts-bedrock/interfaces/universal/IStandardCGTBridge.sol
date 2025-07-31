// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/universal/ISuperchainConfig.sol";

interface IStandardCGTBridge {
    /// @notice Emitted when a ERC20 bridge is initiated on this chain.
    /// @param token     Address of the CGT token.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of CGT sent.
    /// @param extraData Extra data sent with the transaction.
    event ERC20BridgeInitiated(
        address indexed token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Emitted when a ERC20 bridge is finalized on this chain.
    /// @param token     Address of the CGT token.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of CGT sent.
    /// @param extraData Extra data sent with the transaction.
    event ERC20BridgeFinalized(
        address indexed token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Mapping that stores deposits for a given CGT token.
    function deposits(address) external view returns (uint256);

    /// @notice Address of the CGT token.
    function cgtToken() external view returns (address);

    /// @notice Messenger contract on this domain.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Corresponding bridge on the other domain.
    function otherBridge() external view returns (IStandardCGTBridge);

    /// @notice Address of the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig);

    /// @notice Returns the paused state of the bridge.
    /// @return True if the bridge is paused, false otherwise.
    function paused() public view virtual returns (bool);

    /// @notice Sends ERC20 tokens to the sender's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20(
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external;

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external;

    /// @notice Finalizes an ERC20 bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external;
}
