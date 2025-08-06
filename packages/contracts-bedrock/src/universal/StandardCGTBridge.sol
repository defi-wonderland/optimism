// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { EOA } from "src/libraries/EOA.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

/// @custom:upgradeable
/// @title StandardCGTBridge
/// @notice StandardCGTBridge is a base contract for the L1 and L2 CGT bridges. It defines common
///         structures and functions for the CGT bridges on both L1 and L2.
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
    uint256[46] private __gap;

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

    /// @notice Thrown when the recipient is not a valid address.
    error InvalidRecipient();

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is not called from an EOA.
    error NotEOA();

    /// @notice Thrown when the caller is not authorized to call the function.
    error Unauthorized();

    /// @notice Modifier to ensure only EOA can call a function.
    modifier onlyEOA() {
        if (!EOA.isSenderEOA()) {
            revert NotEOA();
        }
        _;
    }

    /// @notice Modifier to ensure the caller is the other bridge.
    modifier onlyOtherBridge() {
        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != address(otherBridge)) {
            revert Unauthorized();
        }
        _;
    }

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
