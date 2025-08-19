// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000011
/// @title SequencerFeeVault
/// @notice The SequencerFeeVault is the contract that holds any fees paid to the Sequencer during
///         transaction processing and block production.
contract SequencerFeeVault is FeeVault, ISemver {
    /// @custom:semver 1.5.2
    string public constant version = "1.5.2";

    /// @notice Constructs the SequencerFeeVault contract.
    /// @param _currentRecipient         Wallet that will receive the fees.
    /// @param _currentMinWithdrawAmount Minimum balance for withdrawals.
    /// @param _currentWithdrawNetwork   Network which the recipient will receive fees on.
    constructor(address _currentRecipient, uint256 _currentMinWithdrawAmount, Types.WithdrawalNetwork _currentWithdrawNetwork) FeeVault(_currentRecipient, _currentMinWithdrawAmount, _currentWithdrawNetwork) { }


    /// @custom:legacy
    /// @notice Legacy getter for the recipient address.
    /// @return The recipient address.
    function l1FeeWallet() public view returns (address) {
        return recipient();
    }
}
