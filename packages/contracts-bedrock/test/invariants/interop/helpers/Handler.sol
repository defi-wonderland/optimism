// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup } from "../Setup.sol";
import { Actors } from "./Actors.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Utils } from "../utils/Utils.sol";
import { vm } from "../utils/VM.sol";
import { Hashing } from "src/libraries/Hashing.sol";

contract Handler is Setup {
    /// @notice Event selector for the SentMessage event.
    bytes32 internal constant _SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    struct Message {
        address from;
        uint256 amount;
        uint256 nonce;
    }

    uint256 internal constant _ZERO_VALUE = 0;

    function handler_depositSuperchainWETH(uint256 _value, uint256 _actorIndex) public {
        _value = clampLte(_value, type(uint256).max - SUPER_WETH.totalSupply());

        Actors actor = randomActor(_actorIndex);
        vm.deal(address(actor), _value);

        try actor.directCall(address(SUPER_WETH), _value, abi.encodeWithSelector(SUPER_WETH.deposit.selector)) { }
        catch {
            assert(false);
        }
    }

    function handler_withdrawSuperchainWETH(uint256 _value, uint256 _actorIndex) public {
        Actors actor = randomActor(_actorIndex);
        _value = clampLte(_value, SUPER_WETH.balanceOf(address(actor)));

        try actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.withdraw.selector, _value)
        ) { } catch {
            assert(false);
        }
    }

    function handler_superchainWETHSendETH(address _to, uint256 _value, uint256 _chainId, uint256 _actorIndex) public {
        require(_to != address(0));
        _chainId = clampGt(_chainId, CHAIN_ID_ONE);

        // Get state before call
        Actors actor = randomActor(_actorIndex);
        uint256 actorBalanceBefore = address(actor).balance;
        uint256 sWethBalanceBefore = address(SUPER_WETH).balance;
        uint256 _ethLiquidityBefore = address(ETH_LIQUIDITY).balance;
        uint256 _sWETHTotalSupplyBefore = SUPER_WETH.totalSupply();

        // Clamp the value to prevent an overflow or a revert due to insufficient balance
        _value = clampLte(_value, Utils.min(type(uint256).max - sWethBalanceBefore, actorBalanceBefore));

        try actor.directCall(address(SUPER_WETH), _value, abi.encodeCall(SUPER_WETH.sendETH, (_to, _chainId))) {
            // Check the Ether balances and that the superchain WETH total supply was not modified
            assert(address(actor).balance == actorBalanceBefore - _value);
            assert(address(ETH_LIQUIDITY).balance == _ethLiquidityBefore + _value);
            // The total supply of superchain WETH should not change
            assert(SUPER_WETH.totalSupply() == _sWETHTotalSupplyBefore);
        } catch {
            assert(false);
        }
    }

    function handler_superchainWETHRelayETH(
        Identifier memory _id,
        Message memory _message,
        uint256 _toActorIndex
    )
        public
    {
        // Ensure the id inputs are valid
        _id.origin = address(L2_TO_L2_MESSENGER);
        _id.timestamp = clampBetween(_id.timestamp, CROSS_L2_INBOX.interopStart() + 1, block.timestamp);
        _message.amount = clampLte(_message.amount, address(ETH_LIQUIDITY).balance - address(SUPER_WETH).balance);

        // Get state before the call
        address targetActor = address(randomActor(_toActorIndex));
        uint256 _tagretActorBalanceBefore = address(targetActor).balance;
        uint256 _ethLiquidityBefore = address(ETH_LIQUIDITY).balance;
        uint256 _sWETHTotalSupplyBefore = SUPER_WETH.totalSupply();

        // Build the message
        address messageTarget = address(SUPER_WETH);
        bytes memory message = abi.encodeCall(SUPER_WETH.relayETH, (_message.from, targetActor, _message.amount));
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(SUPER_WETH), message) // data
        );

        // Ensure the message is not already relayed
        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: block.chainid,
            _source: _id.chainId,
            _nonce: _message.nonce,
            _sender: address(SUPER_WETH),
            _target: address(SUPER_WETH),
            _message: message
        });
        require(!L2_TO_L2_MESSENGER.successfulMessages(messageHash));

        Actors actor = randomActor(_toActorIndex);
        try actor.callL2ToL2MessengerRelayMessage(_id, sentMessage) {
            // Check the Ether balances
            assert(targetActor.balance == _tagretActorBalanceBefore + _message.amount);
            assert(address(ETH_LIQUIDITY).balance == _ethLiquidityBefore - _message.amount);
            // The total supply of superchain WETH should not change
            assert(SUPER_WETH.totalSupply() == _sWETHTotalSupplyBefore);
        } catch {
            assert(false);
        }
    }
}
