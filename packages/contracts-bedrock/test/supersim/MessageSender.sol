// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract MessageSender {
    // The cross domain messenger
    IL2ToL2CrossDomainMessenger constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    /// @notice Sends 5 messages with pseudo-random targets to a destination chain.
    /// @param _destinationChainId The chain ID to send the messages to.
    function sendMessages(uint256 _destinationChainId) external {
        bytes memory message = bytes("");

        for (uint256 i = 0; i < 5; i++) {
            // Use block number and loop index for a pseudo-random target address
            address target = address(uint160(uint256(keccak256(abi.encodePacked(block.number, i)))));
            MESSENGER.sendMessage(_destinationChainId, target, message);
        }
    }
}
