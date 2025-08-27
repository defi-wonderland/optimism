// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title IL1CGTBridge
/// @notice Interface for the L1CGTBridge contract, responsible for bridging Custom Gas Tokens
///         between L1 and L2. This is the basic interface without legacy withdrawal functionality.
interface IL1CGTBridge {
    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-L2 CGT bridge.
    error OnlyL2CGTBridge();

    /// @notice Thrown when the caller is not the proxy admin or proxy admin owner.
    error ProxyAdminOwnedBase_NotProxyAdminOrProxyAdminOwner();

    /// @notice Thrown when the proxy admin is not found.
    error ProxyAdminOwnedBase_ProxyAdminNotFound();

    /// @notice Thrown when the caller is not the proxy admin.
    error ProxyAdminOwnedBase_NotProxyAdmin();

    /// @notice Thrown when the caller is not the proxy admin owner.
    error ProxyAdminOwnedBase_NotProxyAdminOwner();

    /// @notice Thrown when the caller is not a resolved delegate proxy.
    error ProxyAdminOwnedBase_NotResolvedDelegateProxy();

    /// @notice Thrown when the caller is not the shared proxy admin owner.
    error ProxyAdminOwnedBase_NotSharedProxyAdminOwner();

    /// @notice Thrown when the init version is zero.
    error ReinitializableBase_ZeroInitVersion();

    /// @notice Emitted when the contract is initialized.
    /// @param version The version of the initializer.
    event Initialized(uint8 version);

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
    function initialize(ICrossDomainMessenger _messenger, ISuperchainConfig _superchainConfig) external;

    /// @notice Returns the semantic version of the contract.
    /// @return The version string.
    function version() external view returns (string memory);

    /// @notice Returns the initialization version.
    /// @return The initialization version.
    function initVersion() external view returns (uint8);

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
    function l2CGTBridge() external view returns (address);

    /// @notice Returns the address of the CrossDomainMessenger.
    /// @return Address of the CrossDomainMessenger contract.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Returns the address of the SuperchainConfig contract.
    /// @return Address of the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig);

    /// @notice Returns the address of the proxy admin.
    /// @return Address of the proxy admin contract.
    function proxyAdmin() external view returns (IProxyAdmin);

    /// @notice Returns the address of the proxy admin owner.
    /// @return Address of the proxy admin owner.
    function proxyAdminOwner() external view returns (address);
}
