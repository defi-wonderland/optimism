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
}
