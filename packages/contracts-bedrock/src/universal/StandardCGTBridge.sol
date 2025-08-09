// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @custom:upgradeable
/// @title StandardCGTBridge
/// @notice StandardCGTBridge is a base contract for the L1 and L2 Custom Gas Token bridges.
///         It handles the core bridging logic, including escrowing tokens and managing
///         cross-domain communication for CGT transfers.
abstract contract StandardCGTBridge is Initializable {
    /// @notice Address of the CGT token.
    /// @custom:network-specific
    address public cgtToken;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    StandardCGTBridge public otherBridge;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[50] private __gap;

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

    /// @notice Thrown when the amount to deposit is zero.
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when the recipient address is the zero address.
    error RecipientCannotBeZeroAddress();

    /// @notice Thrown when the function is called from a non-EOA.
    error FunctionCanOnlyBeCalledFromEOA();

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-other bridge.
    error FunctionCanOnlyBeCalledFromOtherBridge();

    /// @notice Thrown when ETH is sent to the bridge.
    error CGTBridge_ETHNotAllowed();

    /// @notice This function should return true if the contract is paused.
    ///         On L1 this function will check the SuperchainConfig for its paused status.
    ///         On L2 this function should be a no-op.
    /// @return Whether or not the contract is paused.
    function paused() public view virtual returns (bool) {
        return false;
    }

    /// @notice Initializer for the StandardCGTBridge.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    function __StandardCGTBridge_init(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge
    )
        internal
        onlyInitializing
    {
        cgtToken = _cgtToken;
        messenger = _messenger;
        otherBridge = _otherBridge;
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external payable virtual;

    /// @notice Sends CGT tokens to a receiver's address on the other chain.s
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual;

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
        external
        virtual;
}
