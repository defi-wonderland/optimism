// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IL1CGTStandardBridge } from "interfaces/L1/IL1CGTStandardBridge.sol";
import { IL2CGTStandardBridge } from "interfaces/L2/IL2CGTStandardBridge.sol";

/// @custom:proxied true
/// @title L1CGTStandardBridge
/// @notice The L1CGTStandardBridge is responsible for transferring Custom Gas Tokens (CGT) from L1
///         to L2 where they are converted to native assets through the LiquidityController system.
///         This bridge escrows CGT tokens on L1 and triggers the minting of equivalent native
///         assets on L2.
contract L1CGTStandardBridge is
    StandardCGTBridge,
    ProxyAdminOwnedBase,
    ReinitializableBase,
    OwnableUpgradeable,
    ISemver,
    IL1CGTStandardBridge
{
    /// @notice Address of the SystemConfig contract.
    ISystemConfig public systemConfig;

    /// @notice Address of the CGT token.
    address public cgtToken;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[49] private __gap;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Constructs the L1CGTStandardBridge contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
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
        public
        reinitializer(initVersion())
    {
        __StandardCGTBridge_init({
            _cgtToken: _cgtToken,
            _messenger: _messenger,
            _otherBridge: _otherBridge,
            _superchainConfig: _superchainConfig
        });

        systemConfig = _systemConfig;
        __Ownable_init();
    }

    /// @inheritdoc ISemver
    /// @custom:semver 1.0.0
    function version() public pure virtual override returns (string memory) {
        return VERSION;
    }

    /// @inheritdoc IL1CGTStandardBridge
    /// @dev This function is used to deposit CGT tokens into the bridge.
    /// @param _amount      Amount of CGT tokens to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit.
    /// @param _extraData   Extra data to forward.
    function depositCGT(
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        override
        onlyEOA
        whenNotPaused
    {
        _initiateCGTDeposit(cgtToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc IL1CGTStandardBridge
    /// @dev This function is used to deposit CGT tokens into the bridge.
    /// @param _to          Address to deposit the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit.
    /// @param _extraData   Extra data to forward.
    function depositCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        override
        whenNotPaused
    {
        _initiateCGTDeposit(cgtToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc IL1CGTStandardBridge
    function finalizeCGTWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        override
        onlyOtherBridge
    {
        _finalizeCGTWithdrawal(_l1Token, _from, _to, _amount, _extraData);
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
                IL2CGTStandardBridge.finalizeCGTDeposit.selector, _token, _from, _to, _amount, _extraData
            ),
            _minGasLimit: _minGasLimit
        });
    }
}
