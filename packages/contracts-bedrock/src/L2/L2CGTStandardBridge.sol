// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IL2CGTStandardBridge } from "interfaces/L2/IL2CGTStandardBridge.sol";
import { IL1CGTStandardBridge } from "interfaces/L1/IL1CGTStandardBridge.sol";
import { INativeAssetLiquidity } from "interfaces/L2/INativeAssetLiquidity.sol";

/// @custom:proxied true
/// @title L2CGTStandardBridge
/// @notice The L2CGTStandardBridge is responsible for converting Custom Gas Tokens (CGT)
///         received from L1 into native assets through the LiquidityController system,
///         and handling withdrawals back to L1.
contract L2CGTStandardBridge is
    StandardCGTBridge,
    ReinitializableBase,
    OwnableUpgradeable,
    ISemver,
    IL2CGTStandardBridge
{
    /// @notice Address of the NativeAssetLiquidity contract.
    INativeAssetLiquidity public nativeAssetLiquidity;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[49] private __gap;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Constructs the L2CGTStandardBridge contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param _otherBridge          Address of the corresponding L1 bridge.
    /// @param _superchainConfig     Address of the SuperchainConfig contract.
    /// @param _nativeAssetLiquidity Address of the NativeAssetLiquidity contract.
    function initialize(
        StandardCGTBridge _otherBridge,
        ISuperchainConfig _superchainConfig,
        INativeAssetLiquidity _nativeAssetLiquidity
    )
        public
        reinitializer(initVersion())
    {
        __StandardCGTBridge_init({
            _messenger: ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER),
            _otherBridge: _otherBridge,
            _superchainConfig: _superchainConfig
        });

        nativeAssetLiquidity = _nativeAssetLiquidity;
        __Ownable_init();
    }

    /// @inheritdoc ISemver
    /// @custom:semver 1.0.0
    function version() public pure virtual override returns (string memory) {
        return VERSION;
    }

    /// @inheritdoc IL2CGTStandardBridge
    function withdrawCGT(
        address _l1Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        override
        onlyEOA
        whenNotPaused
    {
        _initiateCGTWithdrawal(_l1Token, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc IL2CGTStandardBridge
    function withdrawCGTTo(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        override
        whenNotPaused
    {
        _initiateCGTWithdrawal(_l1Token, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc IL2CGTStandardBridge
    function finalizeCGTDeposit(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        override
        onlyOtherBridge
    {
        // Convert CGT tokens to native assets through the liquidity controller
        nativeAssetLiquidity.mintNativeAsset(_to, _amount);

        emit CGTDepositFinalized(_l1Token, _from, _to, _amount, _extraData);
    }

    /// @notice Internal function for initiating a CGT withdrawal.
    /// @param _l1Token     Address of the L1 CGT token being withdrawn.
    /// @param _from        Address of the sender on L2.
    /// @param _to          Address of the recipient on L1.
    /// @param _amount      Amount of the CGT to withdraw.
    /// @param _minGasLimit Minimum gas limit for the withdrawal message on L1.
    /// @param _extraData   Optional data to forward to L1.
    function _initiateCGTWithdrawal(
        address _l1Token,
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

        // Burn native assets through the liquidity controller
        nativeAssetLiquidity.burnNativeAsset(_from, _amount);

        // Emit the CGT withdrawal initiated event
        emit CGTWithdrawalInitiated(_l1Token, _from, _to, _amount, _extraData);

        // Send message to L1 bridge to finalize the withdrawal
        _sendCrossChainMessage(_l1Token, _from, _to, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc StandardCGTBridge
    function _sendCrossChainMessage(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
        override
    {
        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(
                IL1CGTStandardBridge.finalizeCGTWithdrawal.selector, _token, _from, _to, _amount, _extraData
            ),
            _minGasLimit: _minGasLimit
        });
    }
}
