// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IL1CGTStandardBridge } from "interfaces/L1/IL1CGTStandardBridge.sol";

/// @custom:proxied true
/// @title L2CGTStandardBridge
/// @notice The L2CGTStandardBridge
contract L2CGTStandardBridge is Initializable, ISemver {
    /// @notice Emitted when a CGT bridge is initiated on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when a CGT bridge is finalized on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    /// @notice Thrown when the value sent is insufficient for the requested amount.
    error InsufficientValue();

    /// @notice Thrown when the recipient address is the zero address.
    error InvalidRecipient();

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-other bridge.
    error OnlyOtherBridge();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    IL1CGTStandardBridge public otherBridge;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[50] private __gap;

    /// @notice Constructs the L2CGTStandardBridge contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external pure override returns (string memory) {
        return VERSION;
    }

    /// @notice Returns whether the bridge is paused.
    /// @return Whether the bridge is paused.
    function paused() public pure returns (bool) {
        return false;
    }

    /// @notice Initializer.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    function initialize(ICrossDomainMessenger _messenger, IL1CGTStandardBridge _otherBridge) external initializer {
        messenger = _messenger;
        otherBridge = _otherBridge;
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint32 _minGasLimit) external payable {
        if (paused()) {
            revert Paused();
        }

        _to = _to == address(0) ? msg.sender : _to;

        // Burn the native asset liquidity
        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).burn{ value: msg.value }();

        // Send the finalizeBridgeCGT message to the bridge on L1
        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeCall(IL1CGTStandardBridge.finalizeBridgeCGT, (msg.sender, _to, msg.value)),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(msg.sender, _to, msg.value);
    }

    /// @notice Finalizes a CGT bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external {
        if (paused()) {
            revert Paused();
        }

        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != address(otherBridge)) {
            revert OnlyOtherBridge();
        }

        if (_to == address(this) || _to == address(messenger)) {
            revert InvalidRecipient();
        }

        // Mint the native asset liquidity
        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).mint(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }
}
