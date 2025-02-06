// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Types } from "src/libraries/Types.sol";

interface IFeeVault {
    event Withdrawal(uint256 value, address to, address from);
    event Withdrawal(uint256 value, address to, address from, Types.WithdrawalNetwork withdrawalNetwork);

    receive() external payable;

    function MIN_WITHDRAWAL_AMOUNT() external view returns (uint256);
    function RECIPIENT() external view returns (address);
    function WITHDRAWAL_NETWORK() external view returns (Types.WithdrawalNetwork);
    function minWithdrawalAmount() external view returns (uint256 amount_);
    function recipient() external view returns (address recipient_);
    function totalProcessed() external view returns (uint256);
    function withdraw() external;
    function withdrawalNetwork() external view returns (Types.WithdrawalNetwork network_);
    function config()
        external
        view
        returns (address recipient_, uint256 minWithdrawalAmount_, Types.WithdrawalNetwork withdrawalNetwork_);

    function __constructor__() external;
}
