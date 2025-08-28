// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IL1CGTBridge
/// @notice Interface for the L1CGTBridge contract, responsible for bridging Custom Gas Tokens
///         between L1 and L2. This is the basic interface without legacy withdrawal functionality.
interface IL1CGTBridge {
    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-L2 CGT bridge.
    error OnlyL2CGTBridge();

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

    /// @notice Initializes the contract.
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
        external;

    /// @notice Returns the semantic version of the contract.
    /// @return The version string.
    function version() external view returns (string memory);

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
    function cgtToken() external view returns (IERC20);

    /// @notice Returns the address of the corresponding bridge on L2.
    /// @return Address of the L2CGTBridge contract.
    function l2CGTBridge() external view returns (address);

    /// @notice Returns the address of the CrossDomainMessenger.
    /// @return Address of the CrossDomainMessenger contract.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Returns the address of the SuperchainConfig contract.
    /// @return Address of the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig);
}
