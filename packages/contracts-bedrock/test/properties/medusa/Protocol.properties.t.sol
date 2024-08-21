// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TestBase } from "forge-std/Base.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { ProtocolHandler } from "./handlers/Protocol.handler.t.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";

contract ProtocolProperties is ProtocolHandler {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    // TODO: will need rework after
    //   - non-atomic bridge
    //   - `convert`
    /// @custom:property-id 24
    /// @custom:property sum of supertoken total supply across all chains is always equal to convert(legacy, super)-
    /// convert(super, legacy)
    function property_totalSupplyAcrossChainsEqualsMints() external view {
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
            assert(trackedSupply == totalSupply);
        }
    }

    /// @notice deploy a new supertoken with deploy salt determined by params, to the given (of course mocked) chainId
    /// @custom:property-id 14
    /// @custom:property supertoken total supply starts at zero
    function property_DeployNewSupertoken(
        TokenDeployParams memory params,
        uint256 chainId
    )
        external
        validateTokenDeployParams(params)
    {
        chainId = bound(chainId, 0, MAX_CHAINS - 1);
        OptimismSuperchainERC20 supertoken = _deploySupertoken(
            remoteTokens[params.remoteTokenIndex],
            WORDS[params.nameIndex],
            WORDS[params.symbolIndex],
            DECIMALS[params.decimalsIndex],
            chainId
        );
        // 14
        assert(supertoken.totalSupply() == 0);
    }

    /// @custom:property-id 6
    /// @custom:property calls to sendERC20 succeed as long as caller has enough balance
    /// @custom:property-id 22
    /// @custom:property sendERC20 decreases sender balance in source chain and increases receiver balance in
    /// destination chain exactly by the input amount
    /// @custom:property-id 23
    /// @custom:property sendERC20 decreases total supply in source chain and increases it in destination chain exactly
    /// by the input amount
    function property_BridgeSupertoken(
        uint256 fromIndex,
        uint256 recipientIndex,
        uint256 destinationChainId,
        uint256 amount
    )
        external
        withActor(msg.sender)
    {
        destinationChainId = bound(destinationChainId, 0, MAX_CHAINS - 1);
        fromIndex = bound(fromIndex, 0, allSuperTokens.length - 1);
        address recipient = getActorByRawIndex(recipientIndex);
        OptimismSuperchainERC20 sourceToken = OptimismSuperchainERC20(allSuperTokens[fromIndex]);
        OptimismSuperchainERC20 destinationToken =
            MESSENGER.crossChainMessageReceiver(address(sourceToken), destinationChainId);
        // TODO: when implementing non-atomic bridging, allow for the token to
        // not yet be deployed and funds be recovered afterwards.
        require(address(destinationToken) != address(0));
        uint256 sourceBalanceBefore = sourceToken.balanceOf(currentActor());
        uint256 sourceSupplyBefore = sourceToken.totalSupply();
        uint256 destinationBalanceBefore = destinationToken.balanceOf(recipient);
        uint256 destinationSupplyBefore = destinationToken.totalSupply();

        vm.prank(currentActor());
        try sourceToken.sendERC20(recipient, amount, destinationChainId) {
            uint256 sourceBalanceAfter = sourceToken.balanceOf(currentActor());
            uint256 destinationBalanceAfter = destinationToken.balanceOf(recipient);
            // no free mint
            assert(sourceBalanceBefore + destinationBalanceBefore == sourceBalanceAfter + destinationBalanceAfter);
            // 22
            assert(sourceBalanceBefore - amount == sourceBalanceAfter);
            assert(destinationBalanceBefore + amount == destinationBalanceAfter);
            uint256 sourceSupplyAfter = sourceToken.totalSupply();
            uint256 destinationSupplyAfter = destinationToken.totalSupply();
            // 23
            assert(sourceSupplyBefore - amount == sourceSupplyAfter);
            assert(destinationSupplyBefore + amount == destinationSupplyAfter);
        } catch {
            // 6
            assert(address(destinationToken) == address(sourceToken) || sourceBalanceBefore < amount);
        }
    }

    /// @custom:property-id 8
    /// @custom:property calls to sendERC20 with a value of zero dont modify accounting
    // NOTE: should we keep it? will cause the exact same coverage as property_BridgeSupertoken
    function property_SendZeroDoesNotModifyAccounting(
        uint256 fromIndex,
        uint256 recipientIndex,
        uint256 destinationChainId
    )
        external
        withActor(msg.sender)
    {
        destinationChainId = bound(destinationChainId, 0, MAX_CHAINS - 1);
        fromIndex = bound(fromIndex, 0, allSuperTokens.length - 1);
        address recipient = getActorByRawIndex(recipientIndex);
        OptimismSuperchainERC20 sourceToken = OptimismSuperchainERC20(allSuperTokens[fromIndex]);
        OptimismSuperchainERC20 destinationToken =
            MESSENGER.crossChainMessageReceiver(address(sourceToken), destinationChainId);
        // TODO: perhaps the mock should already start ignoring this?
        require(address(destinationToken) != address(0));
        uint256 sourceBalanceBefore = sourceToken.balanceOf(currentActor());
        uint256 sourceSupplyBefore = sourceToken.totalSupply();
        uint256 destinationBalanceBefore = destinationToken.balanceOf(recipient);
        uint256 destinationSupplyBefore = destinationToken.totalSupply();

        vm.prank(currentActor());
        try sourceToken.sendERC20(recipient, 0, destinationChainId) {
            uint256 sourceBalanceAfter = sourceToken.balanceOf(currentActor());
            uint256 destinationBalanceAfter = destinationToken.balanceOf(recipient);
            assert(sourceBalanceBefore == sourceBalanceAfter);
            assert(destinationBalanceBefore == destinationBalanceAfter);
            uint256 sourceSupplyAfter = sourceToken.totalSupply();
            uint256 destinationSupplyAfter = destinationToken.totalSupply();
            assert(sourceSupplyBefore == sourceSupplyAfter);
            assert(destinationSupplyBefore == destinationSupplyAfter);
        } catch {
            assert(address(destinationToken) == address(sourceToken));
        }
    }

    /// @custom:property-id 9
    /// @custom:property calls to relayERC20 with a value of zero dont modify accounting
    function property_RelayZeroDoesNotModifyAccounting(
        uint256 fromIndex,
        uint256 recipientIndex
    )
        external
        withActor(msg.sender)
    {
        fromIndex = bound(fromIndex, 0, allSuperTokens.length - 1);
        address recipient = getActorByRawIndex(recipientIndex);
        OptimismSuperchainERC20 token = OptimismSuperchainERC20(allSuperTokens[fromIndex]);
        uint256 balanceBefore = token.balanceOf(currentActor());
        uint256 supplyBefore = token.totalSupply();

        MESSENGER.setCrossDomainMessageSender(address(token));
        vm.prank(address(MESSENGER));
        try token.relayERC20(currentActor(), recipient, 0) {
            MESSENGER.setCrossDomainMessageSender(address(0));
        } catch {
            MESSENGER.setCrossDomainMessageSender(address(0));
        }
        uint256 balanceAfter = token.balanceOf(currentActor());
        uint256 supplyAfter = token.totalSupply();
        assert(balanceBefore == balanceAfter);
        assert(supplyBefore == supplyAfter);
    }

    /// @custom:property-id 7
    /// @custom:property calls to relayERC20 always succeed as long as the cross-domain caller is valid
    /// @notice this ensures actors cant simply call relayERC20 and get tokens, no matter the system state
    /// but there's still some possible work on how hard we can bork the system state with handlers calling
    /// the L2ToL2CrossDomainMessenger or bridge directly (pending on non-atomic bridging)
    function property_SupERC20RelayERC20AlwaysRevert(
        uint256 tokenIndex,
        address sender,
        address recipient,
        uint256 amount
    )
        external
        withActor(msg.sender)
    {
        // if msg.sender is the L2ToL2CrossDomainMessenger then this will break other invariants
        vm.prank(currentActor());
        try OptimismSuperchainERC20(allSuperTokens[bound(tokenIndex, 0, allSuperTokens.length)]).relayERC20(
            sender, recipient, amount
        ) {
            assert(false);
        } catch { }
    }

    /// @custom:property-id 25
    /// @custom:property supertokens can't be reinitialized
    function property_SupERC20CantBeReinitialized(
        uint256 tokenIndex,
        address remoteToken,
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        external
        withActor(msg.sender)
    {
        vm.prank(currentActor());
        // revert is possible in bound, but is not part of the external call
        try OptimismSuperchainERC20(allSuperTokens[bound(tokenIndex, 0, allSuperTokens.length)]).initialize(
            remoteToken, name, symbol, decimals
        ) {
            assert(false);
        } catch { }
    }
}
