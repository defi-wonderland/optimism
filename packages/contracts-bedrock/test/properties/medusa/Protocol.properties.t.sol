// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TestBase } from "forge-std/Base.sol";

import { ITokenMock } from "@crytic/properties/contracts/ERC20/external/util/ITokenMock.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { CryticERC20ExternalBasicProperties } from
    "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";
import { ProtocolHandler } from "./handlers/Protocol.handler.t.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";

contract ProtocolProperties is ProtocolHandler, CryticERC20ExternalBasicProperties {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /// @dev `token` is the token under test for the ToB properties. This is coupled
    /// to the ProtocolHandler constructor initializing at least one supertoken
    constructor() {
        token = ITokenMock(allSuperTokens[0]);
    }

    /// @dev not that much of a handler, since this only changes which
    /// supertoken the ToB assertions are performed against. Thankfully, they are
    /// implemented in a way that don't require tracking ghost variables or can
    /// break properties defined by us
    function handler_ToBTestOtherToken(uint256 index) external {
        token = ITokenMock(allSuperTokens[bound(index, 0, allSuperTokens.length - 1)]);
    }

    // TODO: will need rework after
    //   - non-atomic bridge
    //   - `convert`
    /// @custom:property-id 24
    /// @custom:property sum of supertoken total supply across all chains is always equal to convert(legacy, super)-
    /// convert(super, legacy)
    function property_totalSupplyAcrossChainsEqualsMints() external view {
        // iterate over unique deploy salts aka supertokens that are supposed to be compatible with each other
        for (uint256 deploySaltIndex; deploySaltIndex < ghost_totalSupplyAcrossChains.length(); deploySaltIndex++) {
            uint256 totalSupply;
            (bytes32 currentSalt, uint256 trackedSupply) = ghost_totalSupplyAcrossChains.at(deploySaltIndex);
            // and then over all the (mocked) chain ids where that supertoken could be deployed
            for (uint256 validChainId; validChainId < MAX_CHAINS; validChainId++) {
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
        public
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
    // @notice is a subset of property_BridgeSupertoken, so we'll just call it
    // instead of re-implementing it. Keeping the function for visibility of the property.
    function property_SendZeroDoesNotModifyAccounting(
        uint256 fromIndex,
        uint256 recipientIndex,
        uint256 destinationChainId
    )
        external
    {
        property_BridgeSupertoken(fromIndex, recipientIndex, destinationChainId, 0);
    }

    /// @custom:property-id 9
    /// @custom:property calls to relayERC20 with a value of zero dont modify accounting
    /// @custom:property-id 7
    /// @custom:property calls to relayERC20 always succeed as long as the cross-domain caller is valid
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
        uint256 balanceSenderBefore = token.balanceOf(currentActor());
        uint256 balanceRecipeintBefore = token.balanceOf(recipient);
        uint256 supplyBefore = token.totalSupply();

        MESSENGER.setCrossDomainMessageSender(address(token));
        vm.prank(address(MESSENGER));
        try token.relayERC20(currentActor(), recipient, 0) {
            MESSENGER.setCrossDomainMessageSender(address(0));
        } catch {
            // should not revert because of 7, and if it *does* revert, I want the test suite
            // to discard the sequence instead of potentially getting another
            // error due to the crossDomainMessageSender being manually set
            assert(false);
        }
        uint256 balanceSenderAfter = token.balanceOf(currentActor());
        uint256 balanceRecipeintAfter = token.balanceOf(recipient);
        uint256 supplyAfter = token.totalSupply();
        assert(balanceSenderBefore == balanceSenderAfter);
        assert(balanceRecipeintBefore == balanceRecipeintAfter);
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
            assert(sender == address(MESSENGER));
            assert(crossDomainMessageSender == token);
            // this would increase the supply across chains without a call to
            // `mint` by the MESSENGER, so I'm reverting the state transition
            require(false);
        } catch {
            assert(sender != address(MESSENGER) || crossDomainMessageSender != token);
            MESSENGER.setCrossDomainMessageSender(address(0));
        }
    }

    /// @custom:property-id 25
    /// @custom:property supertokens can't be reinitialized
    function property_SupERC20CantBeReinitialized(
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
