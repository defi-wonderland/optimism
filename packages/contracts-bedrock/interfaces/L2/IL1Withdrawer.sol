// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";

interface IL1Withdrawer is ISemver {
    event WithdrawalInitiated(uint256 amount, address indexed recipient);

    function MIN_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function RECIPIENT() external view returns (address);
    function WITHDRAWAL_GAS_LIMIT() external view returns (uint256);
    function WITHDRAWAL_DATA() external view returns (bytes memory);

    function __constructor__(
        uint256 _minWithdrawalAmount,
        address _recipient,
        uint256 _withdrawalGasLimit,
        bytes memory _withdrawalData
    ) external;
}