// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { L1CGTBridge } from "src/L1/L1CGTBridge.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @custom:proxied true
/// @title L2CGTBridge
/// @notice The L2CGTBridge handles bridging operations on L2, converting between native assets
///         and L1 ERC20 tokens through cross-chain messaging. It burns native assets when sending
///         to L1 and mints native assets when receiving from L1 via the LiquidityController.
contract L2CGTBridge is Initializable, ISemver {
    /// @notice Address of the corresponding L1 CGT bridge.
    /// @custom:network-specific
    address public immutable l1CGTBridge;

    /// @notice Address of the LiquidityController contract.
    /// @custom:network-specific
    ILiquidityController public immutable liquidityController;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[50] private __gap;

    /// @notice Thrown when the function is called from a non-L1 CGT bridge.
    error OnlyL1CGTBridge();

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
    /// @param _l1CGTBridge      Address of the corresponding L1 bridge.
    /// @param _liquidityController Address of the LiquidityController contract.
    constructor(address _l1CGTBridge, ILiquidityController _liquidityController) {
        l1CGTBridge = _l1CGTBridge;
        liquidityController = _liquidityController;
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _messenger Address of the CrossDomainMessenger on this network.
    function initialize(ICrossDomainMessenger _messenger) external initializer {
        messenger = _messenger;
    }

    /// @notice Sends native assets to a receiver's address on L1.
    /// @param _to          Address to bridge the native assets to.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint32 _minGasLimit) external payable virtual {
        // Burn native assets by depositing into LiquidityController
        liquidityController.burn{ value: msg.value }();

        messenger.sendMessage({
            _target: address(l1CGTBridge),
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
        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != address(l1CGTBridge)) {
            revert OnlyL1CGTBridge();
        }

        liquidityController.mint(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }
}
