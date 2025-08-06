// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ZeroAddress } from "src/libraries/errors/CommonErrors.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @custom:proxied true
/// @title L2CGTStandardBridge
/// @notice The L2CGTStandardBridge
contract L2CGTStandardBridge is StandardCGTBridge, ISemver {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the value sent is insufficient for the requested amount.
    error InsufficientValue();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Constructs the L2CGTStandardBridge contract.
    constructor() StandardCGTBridge() {
        _disableInitializers();
    }

    /// @notice Modifier to ensure the bridge is not paused.
    modifier whenNotPaused() {
        if (paused()) {
            revert Paused();
        }
        _;
    }

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external pure override returns (string memory) {
        return VERSION;
    }

    /// @notice Initializer.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge
    )
        external
        initializer
    {
        __StandardCGTBridge_init({ _cgtToken: _cgtToken, _messenger: _messenger, _otherBridge: _otherBridge });
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGT(uint32 _minGasLimit, bytes calldata _extraData) external payable onlyEOA {
        _initiateBridgeCGT(msg.sender, msg.sender, _minGasLimit, _extraData);
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGTTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable {
        _initiateBridgeCGT(msg.sender, _to, _minGasLimit, _extraData);
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
        override
        whenNotPaused
        onlyOtherBridge
    {
        if (_to == address(this) || _to == address(messenger)) {
            revert InvalidRecipient();
        }

        // Mint the native asset liquidity
        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).mint(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function _initiateBridgeCGT(
        address _from,
        address _to,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        internal
        whenNotPaused
    {
        if (_to == address(0)) {
            revert ZeroAddress();
        }

        // Burn the native asset liquidity
        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).burn{ value: msg.value }();

        // Send the finalizeBridgeCGT message to the bridge on L1
        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeCall(StandardCGTBridge.finalizeBridgeCGT, (_from, _to, msg.value, _extraData)),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(_from, _to, msg.value, _extraData);
    }
}
