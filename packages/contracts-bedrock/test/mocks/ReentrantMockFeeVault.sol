// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Types } from "src/libraries/Types.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

/// @notice Mock fee vault that attempts to trigger withdrawal from a different vault during its own withdrawal.
///         This demonstrates the attack vector where a malicious vault tries to exploit the disbursing window
///         to allow unauthorized withdrawals from other vaults.
contract ReentrantMockFeeVault {
    address public immutable RECIPIENT;
    uint256 public immutable WITHDRAWAL_AMOUNT;
    address payable public immutable TARGET_VAULT;

    constructor(address payable _recipient, uint256 _withdrawalAmount, address payable _targetVault) {
        RECIPIENT = _recipient;
        WITHDRAWAL_AMOUNT = _withdrawalAmount;
        TARGET_VAULT = _targetVault;
    }

    receive() external payable { }

    function withdrawalNetwork() external pure returns (Types.WithdrawalNetwork) {
        return Types.WithdrawalNetwork.L2;
    }

    function recipient() external view returns (address) {
        return RECIPIENT;
    }

    function withdraw() external returns (uint256) {
        // First, send the expected ETH to the FeeSplitter
        (bool success,) = RECIPIENT.call{ value: WITHDRAWAL_AMOUNT }("");
        require(success, "ReentrantMockFeeVault: failed to send ETH");

        // Now attempt to trigger a withdrawal from a different vault
        // This should fail with the new stricter check
        if (TARGET_VAULT != address(0)) {
            try IFeeVault(TARGET_VAULT).withdraw() returns (uint256) {
                // If this succeeds, the attack worked
            } catch {
                // Expected to revert with FeeSplitter_SenderNotCurrentVault
            }
        }

        return WITHDRAWAL_AMOUNT;
    }
}
