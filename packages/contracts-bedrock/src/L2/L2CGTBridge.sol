// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { L1CGTBridge } from "src/L1/L1CGTBridge.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @custom:proxied true
/// @title L2CGTBridge
/// @notice The L2CGTBridge handles bridging operations on L2, converting between native assets
///         and L1 ERC20 tokens through cross-chain messaging. It burns native assets when sending
///         to L1 and mints native assets when receiving from L1 via the LiquidityController.
contract L2CGTBridge is Initializable, ISemver {
    /// @notice Address of the corresponding L1 CGT bridge.
    /// @custom:network-specific
    address public l1CGTBridge;

    /// @notice Address of the LiquidityController contract.
    /// @custom:network-specific
    ILiquidityController public liquidityController;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Flag to control if withdrawals from L2 to L1 are enabled.
    /// @custom:network-specific
    bool public initiateEnabledL2toL1;

    /// @notice Flag to control if finalizing deposits from L1 to L2 is enabled.
    /// @custom:network-specific
    bool public finalizeEnabledL1toL2;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[47] private __gap;

    /// @notice Thrown when the function is called from a non-L1 CGT bridge.
    error OnlyL1CGTBridge();

    /// @notice Thrown when the recipient address is invalid.
    error InvalidRecipient();

    /// @notice Thrown when withdrawals from L2 to L1 are disabled.
    error L2CGTBridge_InitiateDisabled();

    /// @notice Thrown when finalizing deposits from L1 to L2 is disabled.
    error L2CGTBridge_FinalizeDisabled();

    /// @notice Thrown when the caller is unauthorized.
    error L2CGTBridge_Unauthorized();

    /// @notice Emitted when initiate enabled flag is updated.
    /// @param enabled New state of the flag.
    event InitiateEnabledL2toL1Updated(bool enabled);

    /// @notice Emitted when finalize enabled flag is updated.
    /// @param enabled New state of the flag.
    event FinalizeEnabledL1toL2Updated(bool enabled);

    /// @notice Emitted when a CGT bridge is initiated on this chain.
    /// @param from   Address of the sender.
    /// @param to     Address of the receiver.
    /// @param amount Amount of native assets sent.
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when a CGT bridge is finalized on this chain.
    /// @param from   Address of the sender.
    /// @param to     Address of the receiver.
    /// @param amount Amount of native assets sent.
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    function version() public view virtual returns (string memory) {
        return "1.0.0";
    }

    /// @notice Constructs the L2CGTBridge contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _messenger Address of the CrossDomainMessenger on this network.
    /// @param _l1CGTBridge      Address of the corresponding L1 bridge.
    /// @param _liquidityController Address of the LiquidityController contract.
    function initialize(
        ICrossDomainMessenger _messenger,
        ILiquidityController _liquidityController,
        address _l1CGTBridge
    )
        external
        initializer
    {
        messenger = _messenger;
        liquidityController = _liquidityController;
        l1CGTBridge = _l1CGTBridge;

        initiateEnabledL2toL1 = true;
        finalizeEnabledL1toL2 = true;
    }

    /// @notice Sends native assets to a receiver's address on L1.
    /// @param _to          Address to bridge the native assets to.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint32 _minGasLimit) external payable virtual {
        if (!initiateEnabledL2toL1) revert L2CGTBridge_InitiateDisabled();

        // Burn native assets by depositing into LiquidityController
        liquidityController.burn{ value: msg.value }();

        messenger.sendMessage({
            _target: l1CGTBridge,
            _message: abi.encodeCall(L1CGTBridge.finalizeBridgeCGT, (msg.sender, _to, msg.value)),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(msg.sender, _to, msg.value);
    }

    /// @notice Finalizes a CGT bridge from L1 to L2 by minting native assets.
    /// @param _from   Address of the sender.
    /// @param _to     Address of the receiver.
    /// @param _amount Amount of native assets being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external virtual {
        if (!finalizeEnabledL1toL2) revert L2CGTBridge_FinalizeDisabled();

        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != l1CGTBridge) {
            revert OnlyL1CGTBridge();
        }

        if (_to == address(this) || _to == address(messenger)) {
            revert InvalidRecipient();
        }

        liquidityController.mint(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }

    /// @notice Sets the initiate enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the initiate enabled flag.
    function setInitiateEnabledL2toL1(bool _enabled) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L2CGTBridge_Unauthorized();
        }
        initiateEnabledL2toL1 = _enabled;
        emit InitiateEnabledL2toL1Updated(_enabled);
    }

    /// @notice Sets the finalize enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the finalize enabled flag.
    function setFinalizeEnabledL1toL2(bool _enabled) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L2CGTBridge_Unauthorized();
        }
        finalizeEnabledL1toL2 = _enabled;
        emit FinalizeEnabledL1toL2Updated(_enabled);
    }
}
