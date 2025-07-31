// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2CGTStandardBridge
/// @notice Interface for the L2 Custom Gas Token Standard Bridge
interface IL2CGTStandardBridge {
    /// @notice Emitted whenever a withdrawal of CGT from L2 to L1 is initiated.
    /// @param l1Token   Address of the CGT token on L1.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of CGT withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event CGTWithdrawalInitiated(
        address indexed l1Token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Emitted whenever a deposit of CGT from L1 into L2 is finalized.
    /// @param l1Token   Address of the CGT token on L1.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of CGT deposited.
    /// @param extraData Extra data attached to the deposit.
    event CGTDepositFinalized(
        address indexed l1Token, address indexed from, address indexed to, uint256 amount, bytes extraData
    );

    /// @notice Withdraws some amount of CGT native assets to the sender's account on L1.
    /// @param _amount      Amount of the CGT to withdraw.
    /// @param _minGasLimit Minimum gas limit for the withdrawal message on L1.
    /// @param _extraData   Optional data to forward to L1.
    function withdrawCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external;

    /// @notice Withdraws some amount of CGT native assets to a target account on L1.
    /// @param _to          Address of the recipient on L1.
    /// @param _amount      Amount of the CGT to withdraw.
    /// @param _minGasLimit Minimum gas limit for the withdrawal message on L1.
    /// @param _extraData   Optional data to forward to L1.
    function withdrawCGTTo(address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external;

    /// @notice Finalizes a deposit of CGT from L1.
    /// @param _from      Address of the depositor on L1.
    /// @param _to        Address of the recipient on L2.
    /// @param _amount    Amount of the CGT to deposit.
    /// @param _extraData Optional data forwarded from L1.
    function finalizeCGTDeposit(address _from, address _to, uint256 _amount, bytes calldata _extraData) external;
}
