// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";
import { Constants } from "src/libraries/Constants.sol";

// Interfaces
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title UpgradeHandler
/// @notice
contract UpgradeHandler {
    function addDependency(address _supechainConfig, uint256 _chainId, address _systemConfig) external {
        if (msg.sender != Constants.DEPOSITOR_ACCOUNT) revert Unauthorized(); // TODO: check if this is safe enough

        IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES).addDependency(_chainId);

        IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal(
            _supechainConfig,
            400_000, // TODO: find an arbitrary value that is enough
            abi.encodeCall(ISuperchainConfig.addDependency, (_chainId, _systemConfig))
        );
    }
}
