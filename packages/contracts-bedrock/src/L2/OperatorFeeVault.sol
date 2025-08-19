// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x420000000000000000000000000000000000001B
/// @title OperatorFeeVault
/// @notice The OperatorFeeVault accumulates the operator portion of the transaction fees.
contract OperatorFeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.1
    string public constant version = "1.0.1";

    /// @notice Constructs the OperatorFeeVault contract.
    /// @param _currentRecipient         Wallet that will receive the fees.
    /// @param _currentMinWithdrawAmount Minimum balance for withdrawals.
    /// @param _currentWithdrawNetwork   Network which the recipient will receive fees on.
    constructor(address _currentRecipient, uint256 _currentMinWithdrawAmount, Types.WithdrawalNetwork _currentWithdrawNetwork) FeeVault(_currentRecipient, _currentMinWithdrawAmount, _currentWithdrawNetwork) { }

}
