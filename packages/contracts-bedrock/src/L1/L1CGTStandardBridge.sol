// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL2CGTStandardBridge } from "interfaces/L2/IL2CGTStandardBridge.sol";

/// @custom:proxied true
/// @title L1CGTStandardBridge
/// @notice The L1CGTStandardBridge is responsible for transferring Custom Gas Tokens (CGT) from L1
///         to L2 where they are converted to native assets through the LiquidityController system.
///         This bridge escrows CGT tokens on L1 and triggers the minting of equivalent native
///         assets on L2.
contract L1CGTStandardBridge is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ISemver {
    using SafeERC20 for IERC20;

    /// @notice Address of the CGT token.
    /// @custom:network-specific
    address public cgtToken;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    IL2CGTStandardBridge public otherBridge;

    /// @notice Address of the SystemConfig contract.
    /// @custom:network-specific
    ISystemConfig public systemConfig;

    /// @notice Address of the SuperchainConfig contract.
    /// @custom:network-specific
    ISuperchainConfig public superchainConfig;

    /// @notice Reference to the OptimismPortal2 contract.
    /// @custom:network-specific
    IOptimismPortal2 public optimismPortal;

    /// @notice Total amount of CGT tokens deposited.
    uint256 public cgtDeposits;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[50] private __gap;

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

    /// @notice Thrown when the amount to deposit is zero.
    error InvalidAmount();

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-other bridge.
    error OnlyOtherBridge();

    /// @notice Constructs the L1CGTStandardBridge contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external pure returns (string memory) {
        return VERSION;
    }

    /// @notice Returns whether the bridge is paused.
    /// @return Whether the bridge is paused.
    function paused() public view returns (bool) {
        return superchainConfig.paused();
    }

    /// @notice Initializer.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    /// @param _systemConfig     Address of the SystemConfig contract.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    /// @param _optimismPortal   Address of the OptimismPortal2 contract.
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        IL2CGTStandardBridge _otherBridge,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        IOptimismPortal2 _optimismPortal
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        cgtToken = _cgtToken;
        messenger = _messenger;
        otherBridge = _otherBridge;
        systemConfig = _systemConfig;
        superchainConfig = _superchainConfig;
        optimismPortal = _optimismPortal;
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external {
        if (paused()) {
            revert Paused();
        }

        if (_amount == 0) {
            revert InvalidAmount();
        }

        _to = _to == address(0) ? msg.sender : _to;

        IERC20(cgtToken).safeTransferFrom(msg.sender, address(this), _amount);
        cgtDeposits = cgtDeposits + _amount;

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(this.finalizeBridgeCGT.selector, msg.sender, _to, _amount),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(msg.sender, _to, _amount);
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

        if (msg.sender != address(messenger)) {
            revert OnlyOtherBridge();
        }
        if (messenger.xDomainMessageSender() != address(otherBridge)) {
            revert OnlyOtherBridge();
        }

        cgtDeposits = cgtDeposits - _amount;
        IERC20(cgtToken).safeTransfer(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }
}
