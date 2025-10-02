// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { L2CGTBridge } from "src/L2/L2CGTBridge.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @custom:proxied true
/// @title L1CGTBridge
/// @notice The L1CGTBridge is responsible for transferring Custom Gas Tokens (CGT) from L1
///         to L2 where they are converted to native assets through the LiquidityController system.
///         This bridge escrows CGT tokens on L1 and triggers the minting of equivalent native
///         assets on L2.
contract L1CGTBridge is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ISemver {
    using SafeERC20 for IERC20;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    address public l2CGTBridge;

    /// @notice Address of the CGT token.
    /// @custom:network-specific
    IERC20 public cgtToken;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Address of the SuperchainConfig contract.
    /// @custom:network-specific
    ISuperchainConfig public superchainConfig;

    /// @notice Flag to control if deposits from L1 to L2 are enabled.
    /// @custom:network-specific
    bool public depositsEnabledL1toL2;

    /// @notice Flag to control if finalizing withdrawals from L2 to L1 is enabled.
    /// @custom:network-specific
    bool public finalizeEnabledL2toL1;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[47] private __gap;

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when caller is not the authorized L2 CGT Bridge.
    error OnlyL2CGTBridge();

    /// @notice Thrown when deposits from L1 to L2 are disabled.
    error L1CGTBridge_DepositsDisabled();

    /// @notice Thrown when finalizing withdrawals from L2 to L1 is disabled.
    error L1CGTBridge_FinalizeDisabled();

    /// @notice Emitted when deposits enabled flag is updated.
    /// @param enabled New state of the flag.
    event DepositsEnabledL1toL2Updated(bool enabled);

    /// @notice Emitted when finalize enabled flag is updated.
    /// @param enabled New state of the flag.
    event FinalizeEnabledL2toL1Updated(bool enabled);

    /// @notice Emitted when a CGT bridge is initiated on this chain.
    /// @param from   Address of the sender.
    /// @param to     Address of the receiver.
    /// @param amount Amount of token sent.
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when a CGT bridge is finalized on this chain.
    /// @param from   Address of the sender.
    /// @param to     Address of the receiver.
    /// @param amount Amount of token sent.
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    function version() public view virtual returns (string memory) {
        return "1.0.0";
    }

    /// @notice Constructs the L1CGTBridge contract
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _l2CGTBridge      Address of the corresponding bridge on the other network.
    function initialize(
        ICrossDomainMessenger _messenger,
        ISuperchainConfig _superchainConfig,
        IERC20 _cgtToken,
        address _l2CGTBridge
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        messenger = _messenger;
        superchainConfig = _superchainConfig;
        cgtToken = _cgtToken;
        l2CGTBridge = _l2CGTBridge;

        depositsEnabledL1toL2 = true;
        finalizeEnabledL2toL1 = true;
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external virtual {
        if (!depositsEnabledL1toL2) revert L1CGTBridge_DepositsDisabled();
        if (superchainConfig.paused(address(this))) revert Paused();

        cgtToken.safeTransferFrom(msg.sender, address(this), _amount);

        messenger.sendMessage({
            _target: l2CGTBridge,
            _message: abi.encodeCall(L2CGTBridge.finalizeBridgeCGT, (msg.sender, _to, _amount)),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(msg.sender, _to, _amount);
    }

    /// @notice Finalizes a CGT bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external virtual {
        if (!finalizeEnabledL2toL1) revert L1CGTBridge_FinalizeDisabled();
        if (superchainConfig.paused(address(this))) revert Paused();

        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != l2CGTBridge) {
            revert OnlyL2CGTBridge();
        }

        cgtToken.safeTransfer(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }

    /// @notice Sets the deposits enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the deposits enabled flag.
    function setDepositsEnabledL1toL2(bool _enabled) external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        depositsEnabledL1toL2 = _enabled;
        emit DepositsEnabledL1toL2Updated(_enabled);
    }

    /// @notice Sets the finalize enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the finalize enabled flag.
    function setFinalizeEnabledL2toL1(bool _enabled) external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        finalizeEnabledL2toL1 = _enabled;
        emit FinalizeEnabledL2toL1Updated(_enabled);
    }
}
