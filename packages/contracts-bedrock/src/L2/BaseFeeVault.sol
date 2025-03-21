// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";

// Interfaces
import { Types } from "src/libraries/Types.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000019
/// @title BaseFeeVault
/// @notice The BaseFeeVault accumulates the base fee that is paid by transactions.
contract BaseFeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.6.0
    string public constant version = "1.6.0";

    /// @inheritdoc FeeVault
    function config()
        public
        view
        virtual
        override
        returns (address recipient_, uint256 minWithdrawalAmount_, Types.WithdrawalNetwork withdrawalNetwork_)
    {
        bytes memory vaultConfig = L1_BLOCK().getConfig(Types.ConfigType.BASE_FEE_VAULT_CONFIG);
        (recipient_, minWithdrawalAmount_, withdrawalNetwork_) =
            Encoding.decodeFeeVaultConfig(abi.decode(vaultConfig, (bytes32)));
    }
}
