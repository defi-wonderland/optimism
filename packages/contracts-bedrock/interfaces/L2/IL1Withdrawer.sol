// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";

interface IL1Withdrawer is ISemver {
    error L1Withdrawer_OnlyProxyAdminOwner();

    event WithdrawalInitiated(uint256 amount, address indexed recipient);
    event MinWithdrawalAmountUpdated(uint216 oldMinWithdrawalAmount, uint216 newMinWithdrawalAmount);
    event RecipientUpdated(address oldRecipient, address newRecipient);
    event WithdrawalGasLimitUpdated(uint40 oldWithdrawalGasLimit, uint40 newWithdrawalGasLimit);
    event WithdrawalDataUpdated(bytes oldWithdrawalData, bytes newWithdrawalData);

    function minWithdrawalAmount() external view returns (uint216);
    function recipient() external view returns (address);
    function withdrawalGasLimit() external view returns (uint40);
    function withdrawalData() external view returns (bytes memory);

    function setMinWithdrawalAmount(uint216 _newMinWithdrawalAmount) external;
    function setRecipient(address _newRecipient) external;
    function setWithdrawalGasLimit(uint40 _newWithdrawalGasLimit) external;
    function setWithdrawalData(bytes memory _newWithdrawalData) external;

    function __constructor__(
        uint216 _minWithdrawalAmount,
        address _recipient,
        uint40 _withdrawalGasLimit,
        bytes memory _withdrawalData
    ) external;
}