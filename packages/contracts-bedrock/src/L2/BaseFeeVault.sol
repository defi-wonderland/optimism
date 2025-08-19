// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000019
/// @title BaseFeeVault
/// @notice The BaseFeeVault accumulates the base fee that is paid by transactions.
contract BaseFeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.5.2
    string public constant version = "1.5.2";

    /// @notice Constructs the BaseFeeVault contract.
    /// @param _currentRecipient         Wallet that will receive the fees.
    /// @param _currentMinWithdrawAmount Minimum balance for withdrawals.
    /// @param _currentWithdrawNetwrok   Network which the recipient will receive fees on.
    constructor(address _currentRecipient, uint256 _currentMinWithdrawAmount, Types.WithdrawalNetwork _currentWithdrawNetwrok) FeeVault(_currentRecipient, _currentMinWithdrawAmount, _currentWithdrawNetwrok) { }

}
