// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000011
/// @title SequencerFeeVault
/// @notice The SequencerFeeVault is the contract that holds any fees paid to the Sequencer during
///         transaction processing and block production.
contract SequencerFeeVault is FeeVault, ISemver {
    /// @custom:semver 1.5.0-beta.6
    string public constant version = "1.5.0-beta.6";

    /// @custom:legacy
    /// @notice Legacy getter for the recipient address.
    /// @return recipient_ The recipient address.
    function l1FeeWallet() public view returns (address recipient_) {
        (recipient_,,) = config();
    }

    /// @inheritdoc FeeVault
    function config()
        public
        view
        virtual
        override
        returns (address recipient_, uint256 minWithdrawalAmount_, Types.WithdrawalNetwork withdrawalNetwork_)
    {
        bytes memory vaultConfig = L1_BLOCK().getConfig(Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG);
        (recipient_, minWithdrawalAmount_, withdrawalNetwork_) =
            Encoding.decodeFeeVaultConfig(abi.decode(vaultConfig, (bytes32)));
    }
}
