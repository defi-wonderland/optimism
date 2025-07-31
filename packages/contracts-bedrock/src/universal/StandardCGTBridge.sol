// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EOA } from "src/libraries/EOA.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @notice Thrown when a token is not supported for CGT bridging.
error StandardCGTBridge_TokenNotSupported();

/// @notice Thrown when the amount to deposit is zero.
error StandardCGTBridge_AmountMustBeGreaterThanZero();

/// @notice Thrown when the recipient address is the zero address.
error StandardCGTBridge_RecipientCannotBeZeroAddress();

/// @notice Thrown when the function is called from a non-EOA.
error StandardCGTBridge_FunctionCanOnlyBeCalledFromEOA();

/// @notice Thrown when the bridge is paused.
error StandardCGTBridge_Paused();

/// @notice Thrown when the function is called from a non-other bridge.
error StandardCGTBridge_FunctionCanOnlyBeCalledFromOtherBridge();

/// @notice Thrown when the deposits are insufficient.
error StandardCGTBridge_InsufficientDeposits();

/// @notice Thrown when the daily deposit limit is exceeded.
error StandardCGTBridge_ExceedsDailyDepositLimit();

/// @custom:upgradeable
/// @title StandardCGTBridge
/// @notice StandardCGTBridge is a base contract for the L1 and L2 Custom Gas Token bridges.
///         It handles the core bridging logic, including escrowing tokens and managing
///         cross-domain communication for CGT transfers.
abstract contract StandardCGTBridge is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Mapping that stores deposits for a given CGT token.
    mapping(address => uint256) public deposits;

    /// @notice Address of the CGT token.
    address public cgtToken;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    StandardCGTBridge public otherBridge;

    /// @notice Address of the SuperchainConfig contract.
    ISuperchainConfig public superchainConfig;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[45] private __gap;

    /// @notice Emitted when a CGT deposit is initiated to the other chain.
    /// @param token     Address of the CGT token.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of CGT sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTDepositInitiated(
        address indexed token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Emitted when a CGT withdrawal is finalized on this chain.
    /// @param token     Address of the CGT token.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of CGT sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTWithdrawalFinalized(
        address indexed token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Modifier to ensure only EOA can call a function.
    modifier onlyEOA() {
        if (!EOA.isEOA(msg.sender)) {
            revert StandardCGTBridge_FunctionCanOnlyBeCalledFromEOA();
        }
        _;
    }

    /// @notice Modifier to ensure the system is not paused.
    modifier whenNotPaused() {
        if (paused()) {
            revert StandardCGTBridge_Paused();
        }
        _;
    }

    /// @notice Modifier to ensure the caller is the other bridge.
    modifier onlyOtherBridge() {
        if (msg.sender != address(messenger)) {
            revert StandardCGTBridge_FunctionCanOnlyBeCalledFromOtherBridge();
        }
        if (messenger.xDomainMessageSender() != address(otherBridge)) {
            revert StandardCGTBridge_FunctionCanOnlyBeCalledFromOtherBridge();
        }
        _;
    }

    /// @notice Initializer for the StandardCGTBridge.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    function __StandardCGTBridge_init(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge,
        ISuperchainConfig _superchainConfig
    )
        internal
        onlyInitializing
    {
        cgtToken = _cgtToken;
        messenger = _messenger;
        otherBridge = _otherBridge;
        superchainConfig = _superchainConfig;
    }

    /// @notice Checks whether the bridge is paused.
    /// @return Whether the bridge is paused.
    function paused() public view virtual returns (bool) {
        return superchainConfig.paused();
    }

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
        public
        virtual
        onlyEOA
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

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
        public
        virtual
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

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
        public
        onlyOtherBridge
    {
        if (paused()) {
            revert StandardCGTBridge_Paused();
        }

        deposits[_localToken] = deposits[_localToken] - _amount;
        IERC20(_localToken).safeTransfer(_to, _amount);

        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        if (_amount == 0) {
            revert StandardCGTBridge_AmountMustBeGreaterThanZero();
        }

        if (_to == address(0)) {
            revert StandardCGTBridge_RecipientCannotBeZeroAddress();
        }

        if (_localToken == cgtToken) revert StandardCGTBridge_TokenNotSupported();

        IERC20(_localToken).safeTransferFrom(_from, address(this), _amount);
        deposits[_localToken] = deposits[_localToken] + _amount;

        emit CGTDepositInitiated(_localToken, _from, _to, _amount, _extraData);

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(
                this.finalizeBridgeERC20.selector,
                // Because this call will be executed on the remote chain, we reverse the order of
                // the remote and local token addresses relative to their order in the
                // finalizeBridgeERC20 function.
                _remoteToken,
                _localToken,
                _from,
                _to,
                _amount,
                _extraData
            ),
            _minGasLimit: _minGasLimit
        });
    }
}
