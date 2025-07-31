// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL1CGTStandardBridge
/// @notice Interface for the L1 Custom Gas Token Standard Bridge
interface IL1CGTStandardBridge {
    /// @notice Emitted whenever a deposit of CGT from L1 into L2 is initiated.
    /// @param l1Token   Address of the CGT token on L1.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of CGT deposited.
    /// @param extraData Extra data attached to the deposit.
    event CGTDepositInitiated(
        address indexed l1Token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Emitted whenever a withdrawal of CGT from L2 to L1 is finalized.
    /// @param l1Token   Address of the CGT token on L1.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of CGT withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event CGTWithdrawalFinalized(
        address indexed l1Token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Deposits some amount of CGT tokens into the sender's account on L2.
    /// @param _amount      Amount of the CGT to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    function depositCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external;

    /// @notice Deposits some amount of CGT tokens into a target account on L2.
    /// @param _to          Address of the recipient on L2.
    /// @param _amount      Amount of the CGT to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    function depositCGTTo(address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external;

    /// @notice Finalizes a withdrawal of CGT from L2.
    /// @param _from      Address of the withdrawer on L2.
    /// @param _to        Address of the recipient on L1.
    /// @param _amount    Amount of the CGT to withdraw.
    /// @param _extraData Optional data forwarded from L2.
    function finalizeCGTWithdrawal(address _from, address _to, uint256 _amount, bytes calldata _extraData) external;
}
