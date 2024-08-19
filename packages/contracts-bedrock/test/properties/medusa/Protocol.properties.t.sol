// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProtocolHandler } from "./handlers/Protocol.handler.t.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract ProtocolProperties is ProtocolHandler {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
    // TODO: will need rework after
    //   - non-atomic bridge
    //   - `convert`
    /// @custom:property-id 24
    /// @custom:property sum of supertoken total supply across all chains is always equal to convert(legacy, super)-
    /// convert(super, legacy)

    function property_totalSupplyAcrossChainsEqualsMints() external view returns (bool success) {
        // iterate over unique deploy salts aka supertokens that are supposed to be compatible with each other
        for (uint256 deploySaltIndex = 0; deploySaltIndex < ghost_totalSupplyAcrossChains.length(); deploySaltIndex++) {
            uint256 totalSupply = 0;
            (bytes32 currentSalt, uint256 trackedSupply) = ghost_totalSupplyAcrossChains.at(deploySaltIndex);
            // and then over all the (mocked) chain ids where that supertoken could be deployed
            for (uint256 validChainId = 0; validChainId < MAX_CHAINS; validChainId++) {
                address supertoken = MESSENGER.superTokenAddresses(validChainId, currentSalt);
                if (supertoken != address(0)) {
                    totalSupply += OptimismSuperchainERC20(supertoken).totalSupply();
                }
            }
            if (trackedSupply != totalSupply) {
                return false;
            }
        }
        return true;
    }
}
