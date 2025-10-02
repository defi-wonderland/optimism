// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title IL2CGTBridge
/// @notice Interface for the L2CGTBridge contract, responsible for bridging native assets
///         between L2 and L1 ERC20 tokens through cross-chain messaging.
interface IL2CGTBridge {
    /// @notice Thrown when the function is called from a non-L1 CGT bridge.
    error OnlyL1CGTBridge();

    /// @notice Thrown when the recipient address is invalid.
    error InvalidRecipient();

    /// @notice Thrown when withdrawals from L2 to L1 are disabled.
    error L2CGTBridge_InitiateDisabled();

    /// @notice Thrown when finalizing deposits from L1 to L2 is disabled.
    error L2CGTBridge_FinalizeDisabled();

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

    /// @notice Initializes the contract.
    /// @param _messenger Address of the CrossDomainMessenger on this network.
    /// @param _liquidityController Address of the LiquidityController contract.
    /// @param _l1CGTBridge Address of the corresponding L1 bridge.
    function initialize(
        ICrossDomainMessenger _messenger,
        ILiquidityController _liquidityController,
        address _l1CGTBridge
    )
        external;

    /// @notice Returns the semantic version of the contract.
    /// @return The version string.
    function version() external view returns (string memory);

    /// @notice Initiates a native asset transfer from L2 to L1.
    /// @param _to          Address to receive the ERC20 tokens on L1.
    /// @param _minGasLimit Minimum gas limit for the cross-domain message.
    function bridgeCGT(address _to, uint32 _minGasLimit) external payable;

    /// @notice Finalizes a CGT transfer from L1 to L2.
    /// @param _from   Address of the sender on L1.
    /// @param _to     Address of the receiver on L2.
    /// @param _amount Amount of native assets being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;

    /// @notice Returns the address of the corresponding bridge on L1.
    /// @return Address of the L1CGTBridge contract.
    function l1CGTBridge() external view returns (address);

    /// @notice Returns the address of the CrossDomainMessenger.
    /// @return Address of the CrossDomainMessenger contract.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Returns the address of the LiquidityController.
    /// @return Address of the LiquidityController contract.
    function liquidityController() external view returns (ILiquidityController);

    /// @notice Returns the initiate enabled flag.
    /// @return True if withdrawals from L2 to L1 are enabled.
    function initiateEnabledL2toL1() external view returns (bool);

    /// @notice Returns the finalize enabled flag.
    /// @return True if finalizing deposits from L1 to L2 is enabled.
    function finalizeEnabledL1toL2() external view returns (bool);

    /// @notice Sets the initiate enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the initiate enabled flag.
    function setInitiateEnabledL2toL1(bool _enabled) external;

    /// @notice Sets the finalize enabled flag.
    /// @dev Only callable by ProxyAdmin or its owner.
    /// @param _enabled New state of the finalize enabled flag.
    function setFinalizeEnabledL1toL2(bool _enabled) external;
}
