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
/// @custom:predeploy 0x420000000000000000000000000000000000001B
/// @title OperatorFeeVault
/// @notice The OperatorFeeVault accumulates the operator portion of the transaction fees.
contract OperatorFeeVault is FeeVault, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.1.0
    string public constant version = "1.1.0";

    /// @inheritdoc FeeVault
    function config()
        public
        view
        override
        returns (address recipient_, uint256 minWithdrawalAmount_, Types.WithdrawalNetwork withdrawalNetwork_)
    {
        bytes memory vaultConfig = L1_BLOCK().getConfig(Types.ConfigType.OPERATOR_FEE_VAULT_CONFIG);
        (recipient_, minWithdrawalAmount_, withdrawalNetwork_) =
            Encoding.decodeFeeVaultConfig(abi.decode(vaultConfig, (bytes32)));
    }
}
