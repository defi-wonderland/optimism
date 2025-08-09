// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EOA } from "src/libraries/EOA.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @custom:proxied true
/// @title L1CGTStandardBridge
/// @notice The L1CGTStandardBridge is responsible for transferring Custom Gas Tokens (CGT) from L1
///         to L2 where they are converted to native assets through the LiquidityController system.
///         This bridge escrows CGT tokens on L1 and triggers the minting of equivalent native
///         assets on L2.
contract L1CGTStandardBridge is StandardCGTBridge, ProxyAdminOwnedBase, ReinitializableBase, ISemver {
    using SafeERC20 for IERC20;

    /// @notice Address of the SystemConfig contract.
    /// @custom:network-specific
    ISystemConfig public systemConfig;

    /// @notice Address of the SuperchainConfig contract.
    /// @custom:network-specific
    ISuperchainConfig public superchainConfig;

    /// @notice Total amount of CGT tokens deposited.
    uint256 public cgtDeposits;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Constructs the L1CGTStandardBridge contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external pure override returns (string memory) {
        return VERSION;
    }

    /// @notice Returns whether the bridge is paused.
    /// @return Whether the bridge is paused.
    function paused() public view override returns (bool) {
        return superchainConfig.paused();
    }

    /// @notice Initializer.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    /// @param _systemConfig     Address of the SystemConfig contract.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        systemConfig = _systemConfig;
        superchainConfig = _superchainConfig;
        __StandardCGTBridge_init({ _cgtToken: _cgtToken, _messenger: _messenger, _otherBridge: _otherBridge });
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external payable override {
        _initiateBridgeCGT(msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        override
    {
        _initiateBridgeCGT(msg.sender, _to, _amount, _minGasLimit, _extraData);
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
    {
        if (paused()) {
            revert Paused();
        }

        if (msg.sender != address(messenger)) {
            revert FunctionCanOnlyBeCalledFromOtherBridge();
        }
        if (messenger.xDomainMessageSender() != address(otherBridge)) {
            revert FunctionCanOnlyBeCalledFromOtherBridge();
        }

        cgtDeposits = cgtDeposits - _amount;
        IERC20(cgtToken).safeTransfer(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function _initiateBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        internal
    {
        if (!EOA.isSenderEOA()) {
            revert FunctionCanOnlyBeCalledFromEOA();
        }

        if (paused()) {
            revert Paused();
        }

        if (msg.value > 0) {
            revert CGTBridge_ETHNotAllowed();
        }

        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        if (_to == address(0)) {
            revert RecipientCannotBeZeroAddress();
        }

        IERC20(cgtToken).safeTransferFrom(_from, address(this), _amount);
        cgtDeposits = cgtDeposits + _amount;

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(this.finalizeBridgeCGT.selector, _from, _to, _amount, _extraData),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(_from, _to, _amount, _extraData);
    }
}
