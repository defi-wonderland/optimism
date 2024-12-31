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
/// @custom:predeploy 0x420000000000000000000000000000000000001A
/// @title L1FeeVault
/// @notice The L1FeeVault accumulates the L1 portion of the transaction fees.
contract L1FeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.5.0-beta.6
    string public constant version = "1.5.0-beta.6";

    /// @inheritdoc FeeVault
    function config()
        public
        view
        virtual
        override
        returns (address recipient_, uint256 minWithdrawalAmount_, Types.WithdrawalNetwork withdrawalNetwork_)
    {
        bytes memory vaultConfig = L1_BLOCK().getConfig(Types.ConfigType.L1_FEE_VAULT_CONFIG);
        (recipient_, minWithdrawalAmount_, withdrawalNetwork_) =
            Encoding.decodeFeeVaultConfig(abi.decode(vaultConfig, (bytes32)));
    }
}
