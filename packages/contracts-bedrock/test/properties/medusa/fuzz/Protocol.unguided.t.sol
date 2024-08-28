// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProtocolHandler } from "../handlers/Protocol.t.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";

// TODO: add fuzz_sendERC20 when we implement non-atomic bridging
contract ProtocolUnguided is ProtocolHandler {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /// @custom:property-id 7
    /// @custom:property calls to relayERC20 always succeed as long as the cross-domain caller is valid
    /// @notice this ensures actors cant simply call relayERC20 and get tokens, no matter the system state
    /// but there's still some possible work on how hard we can bork the system state with handlers calling
    /// the L2ToL2CrossDomainMessenger or bridge directly (pending on non-atomic bridging)
    function fuzz_relayERC20(
        uint256 tokenIndex,
        address sender,
        address crossDomainMessageSender,
        address recipient,
        uint256 amount
    )
        external
    {
        MESSENGER.setCrossDomainMessageSender(crossDomainMessageSender);
        address token = allSuperTokens[bound(tokenIndex, 0, allSuperTokens.length)];
        vm.prank(sender);
        try OptimismSuperchainERC20(token).relayERC20(sender, recipient, amount) {
            MESSENGER.setCrossDomainMessageSender(address(0));
            assert(sender == address(MESSENGER));
            assert(crossDomainMessageSender == token);
            // this increases the supply across chains without a call to
            // `mint` by the MESSENGER, so it kind of breaks an invariant, but
            // let's walk around that:
            bytes32 salt = MESSENGER.superTokenInitDeploySalts(token);
            (, uint256 currentValue) = ghost_totalSupplyAcrossChains.tryGet(salt);
            ghost_totalSupplyAcrossChains.set(salt, currentValue + amount);
        } catch {
            assert(sender != address(MESSENGER) || crossDomainMessageSender != token);
            MESSENGER.setCrossDomainMessageSender(address(0));
        }
    }

    /// @custom:property-id 25
    /// @custom:property supertokens can't be reinitialized
    function fuzz_initialize(
        address sender,
        uint256 tokenIndex,
        address remoteToken,
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        external
    {
        vm.prank(sender);
        // revert is possible in bound, but is not part of the external call
        try OptimismSuperchainERC20(allSuperTokens[bound(tokenIndex, 0, allSuperTokens.length)]).initialize(
            remoteToken, name, symbol, decimals
        ) {
            assert(false);
        } catch { }
    }
}
