// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IStandardCGTBridge } from "interfaces/universal/IStandardCGTBridge.sol";

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge {
    /// @notice Emitted when a CGT bridge is initiated on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when a CGT bridge is finalized on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of token sent.
    /// @param extraData Extra data sent with the transaction.
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Thrown when the amount to deposit is zero.
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when the recipient address is the zero address.
    error RecipientCannotBeZeroAddress();

    /// @notice Thrown when the function is called from a non-EOA.
    error FunctionCanOnlyBeCalledFromEOA();

    /// @notice Thrown when the bridge is paused.
    error Paused();

    /// @notice Thrown when the function is called from a non-other bridge.
    error FunctionCanOnlyBeCalledFromOtherBridge();

    /// @notice Thrown when ETH is sent to the bridge.
    error CGTBridge_ETHNotAllowed();

    /// @notice Address of the CGT token.
    function cgtToken() external view returns (address);

    /// @notice Messenger contract on this domain.
    function messenger() external view returns (ICrossDomainMessenger);

    /// @notice Corresponding bridge on the other domain.
    function otherBridge() external view returns (IStandardCGTBridge);

    function superchainConfig() external view returns (ISuperchainConfig);

    function optimismPortal() external view returns (IOptimismPortal2);

    function cgtDeposits() external view returns (uint256);

    function VERSION() external view returns (string memory);

    /// @notice Returns the paused state of the bridge.
    /// @return True if the bridge is paused, false otherwise.
    function paused() external view returns (bool);

    function bridgeCGTTo(address _to, uint256 _amount, uint32 _minGasLimit) external;

    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;
}
