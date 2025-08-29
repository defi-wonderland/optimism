// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title L1Withdrawer
/// @notice A contract that receives ETH and automatically initiates withdrawals to L1 when a
///         minimum balance threshold is reached. This contract is designed to be used as a
///         recipient for the FeeSplitter contract and is part of the revenue sharing standard contracts.
contract L1Withdrawer is ISemver {
    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error L1Withdrawer_OnlyProxyAdminOwner();

    /// @notice The minimum amount of ETH that must be accumulated before a withdrawal is initiated.
    uint256 public minWithdrawalAmount;

    /// @notice The L1 address that will receive the withdrawn ETH.
    address public recipient;

    /// @notice The L1 gas limit set when initiating withdrawals.
    uint256 public withdrawalGasLimit;

    /// @notice The data to be sent with the withdrawal transaction.
    bytes public withdrawalData;

    /// @notice Emitted when a withdrawal to L1 is initiated.
    /// @param amount The amount of ETH being withdrawn.
    /// @param recipient The L1 address receiving the withdrawal.
    event WithdrawalInitiated(uint256 amount, address indexed recipient);

    /// @notice Emitted when the minimum withdrawal amount is updated.
    /// @param oldMinWithdrawalAmount The previous minimum withdrawal amount.
    /// @param newMinWithdrawalAmount The new minimum withdrawal amount.
    event MinWithdrawalAmountUpdated(uint256 oldMinWithdrawalAmount, uint256 newMinWithdrawalAmount);

    /// @notice Emitted when the recipient is updated.
    /// @param oldRecipient The previous recipient address.
    /// @param newRecipient The new recipient address.
    event RecipientUpdated(address oldRecipient, address newRecipient);

    /// @notice Emitted when the withdrawal gas limit is updated.
    /// @param oldWithdrawalGasLimit The previous withdrawal gas limit.
    /// @param newWithdrawalGasLimit The new withdrawal gas limit.
    event WithdrawalGasLimitUpdated(uint256 oldWithdrawalGasLimit, uint256 newWithdrawalGasLimit);

    /// @notice Emitted when the withdrawal data is updated.
    /// @param oldWithdrawalData The previous withdrawal data.
    /// @param newWithdrawalData The new withdrawal data.
    event WithdrawalDataUpdated(bytes oldWithdrawalData, bytes newWithdrawalData);

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
        minWithdrawalAmount = _minWithdrawalAmount;
        recipient = _recipient;
        withdrawalGasLimit = _withdrawalGasLimit;
        withdrawalData = _withdrawalData;
    }

    /// @notice Receives ETH and initiates a withdrawal to L1 if the balance meets the threshold.
    receive() external payable {
        uint256 balance = address(this).balance;

        if (balance >= minWithdrawalAmount) {
            emit WithdrawalInitiated(balance, recipient);

            IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{ value: balance }(
                recipient, withdrawalGasLimit, withdrawalData
            );
        }
    }

    /// @notice Updates the minimum withdrawal amount. Only callable by the ProxyAdmin owner.
    /// @param _newMinWithdrawalAmount The new minimum withdrawal amount.
    function setMinWithdrawalAmount(uint256 _newMinWithdrawalAmount) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L1Withdrawer_OnlyProxyAdminOwner();
        }
        // TODO: consider sanity checks to avoid DoS with very high minWithdrawalAmount
        uint256 oldMinWithdrawalAmount = minWithdrawalAmount;
        minWithdrawalAmount = _newMinWithdrawalAmount;
        emit MinWithdrawalAmountUpdated(oldMinWithdrawalAmount, _newMinWithdrawalAmount);
    }

    /// @notice Updates the recipient address. Only callable by the ProxyAdmin owner.
    /// @param _newRecipient The new recipient address.
    function setRecipient(address _newRecipient) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L1Withdrawer_OnlyProxyAdminOwner();
        }
        address oldRecipient = recipient;
        recipient = _newRecipient;
        emit RecipientUpdated(oldRecipient, _newRecipient);
    }

    /// @notice Updates the withdrawal gas limit. Only callable by the ProxyAdmin owner.
    /// @param _newWithdrawalGasLimit The new withdrawal gas limit.
    function setWithdrawalGasLimit(uint256 _newWithdrawalGasLimit) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L1Withdrawer_OnlyProxyAdminOwner();
        }
        uint256 oldWithdrawalGasLimit = withdrawalGasLimit;
        withdrawalGasLimit = _newWithdrawalGasLimit;
        emit WithdrawalGasLimitUpdated(oldWithdrawalGasLimit, _newWithdrawalGasLimit);
    }

    /// @notice Updates the withdrawal data. Only callable by the ProxyAdmin owner.
    /// @param _newWithdrawalData The new withdrawal data.
    function setWithdrawalData(bytes memory _newWithdrawalData) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert L1Withdrawer_OnlyProxyAdminOwner();
        }
        bytes memory oldWithdrawalData = withdrawalData;
        withdrawalData = _newWithdrawalData;
        emit WithdrawalDataUpdated(oldWithdrawalData, _newWithdrawalData);
    }
}
