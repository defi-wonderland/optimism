// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

/// @title IL1CGTBridge
/// @notice Interface for the L1CGTBridge contract, responsible for bridging Custom Gas Tokens
///         between L1 and L2. This is the basic interface without legacy withdrawal functionality.
interface IL1CGTBridge {
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

    /// @notice Initiates a CGT transfer from L1 to L2.
    /// @param _to          Address to receive the CGT tokens on L2.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the cross-domain message.
    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external;

    /// @notice Finalizes a CGT transfer from L2 to L1.
    /// @param _from   Address of the sender on L2.
    /// @param _to     Address of the receiver on L1.
    /// @param _amount Amount of CGT tokens being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;

    /// @notice Returns the address of the CGT token.
    /// @return Address of the CGT token contract.
    function cgtToken() external view returns (address);

    /// @notice Returns the address of the corresponding bridge on L2.
    /// @return Address of the L2CGTBridge contract.
    function otherBridge() external view returns (address);

    /// @notice Returns the address of the CrossDomainMessenger.
    /// @return Address of the CrossDomainMessenger contract.
    function messenger() external view returns (ICrossDomainMessenger);
}