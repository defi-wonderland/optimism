// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title L1Withdrawer
/// @notice A contract that receives ETH and automatically initiates withdrawals to L1 when a
///         minimum balance threshold is reached. This contract is designed to be used as a
///         recipient for the FeeSplitter contract and is part of the revenue sharing standard contracts.
contract L1Withdrawer is ISemver {
    /// @notice The minimum amount of ETH that must be accumulated before a withdrawal is initiated.
    uint256 public immutable MIN_WITHDRAWAL_AMOUNT;

    /// @notice The L1 address that will receive the withdrawn ETH.
    address public immutable RECIPIENT;

    /// @notice The L1 gas limit set when initiating withdrawals.
    uint256 public immutable WITHDRAWAL_GAS_LIMIT;

    /// @notice The data to be sent with the withdrawal transaction.
    bytes public WITHDRAWAL_DATA; // non-value type, not possible to make immutable

    /// @notice Emitted when a withdrawal to L1 is initiated.
    /// @param amount The amount of ETH being withdrawn.
    /// @param recipient The L1 address receiving the withdrawal.
    event WithdrawalInitiated(uint256 amount, address indexed recipient);

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Constructs the L1Withdrawer contract.
    /// @param _minWithdrawalAmount The minimum amount of ETH required to trigger a withdrawal.
    /// @param _recipient The L1 address that will receive withdrawals.
    /// @param _withdrawalGasLimit The gas limit for the L1 withdrawal transaction.
    /// @param _withdrawalData The data to be sent with the withdrawal transaction.
    constructor(
        uint256 _minWithdrawalAmount,
        address _recipient,
        uint256 _withdrawalGasLimit,
        bytes memory _withdrawalData
    ) {
        MIN_WITHDRAWAL_AMOUNT = _minWithdrawalAmount;
        RECIPIENT = _recipient;
        WITHDRAWAL_GAS_LIMIT = _withdrawalGasLimit;
        WITHDRAWAL_DATA = _withdrawalData;
    }

    /// @notice Receives ETH and initiates a withdrawal to L1 if the balance meets the threshold.
    receive() external payable {
        uint256 balance = address(this).balance;

        if (balance >= MIN_WITHDRAWAL_AMOUNT) {
            emit WithdrawalInitiated(balance, RECIPIENT);

            IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{ value: balance }(
                RECIPIENT, WITHDRAWAL_GAS_LIMIT, WITHDRAWAL_DATA
            );
        }
    }
}
