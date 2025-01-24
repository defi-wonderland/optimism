// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup, Preinstalls } from "../Setup.sol";
import { Actors } from "./Actors.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Permit2Mock as Permit2 } from "../mocks/Permit2Mock.sol";
import { Utils } from "../utils/Utils.sol";
import { vm } from "../utils/VM.sol";
import { Hashing } from "src/libraries/Hashing.sol";

contract Handler is Setup {
    mapping(address => uint256) public nonces;

    bool initialized;

    /// NOTE: Using this modifier because the initialization is not working when called inside the constructor on medusa
    modifier isInitialized() {
        if (!initialized) {
            _initializeProxies();
            initialized = true;
        }
        _;
    }

    /// @notice Event selector for the SentMessage event.
    bytes32 internal constant _SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct Message {
        address from;
        uint256 amount;
        uint256 nonce;
    }

    uint256 internal constant _ZERO_VALUE = 0;

    function handler_transferSuperchainERC20(address _to, uint256 _amount, uint256 _actorIndex) public isInitialized {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(actor)));

        try actor.directCall(
            address(SUPER_TOKEN), _ZERO_VALUE, abi.encodeWithSelector(SUPER_TOKEN.transfer.selector, _to, _amount)
        ) { } catch {
            assert(false);
        }
    }

    function handler_transferFromSuperchainERC20(
        uint256 _fromActorIndex,
        uint256 _callerActorIndex,
        address _to,
        uint256 _amount
    )
        public
        isInitialized
    {
        Actors fromActor = randomActor(_fromActorIndex);
        Actors callerActor = randomActor(_callerActorIndex);
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(fromActor)));

        // Approve the spender to transfer the tokens
        try fromActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.approve.selector, address(callerActor), _amount)
        ) { } catch {
            assert(false);
        }

        // Transfer the tokens
        try callerActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.transferFrom.selector, address(fromActor), _to, _amount)
        ) { } catch {
            assert(false);
        }
    }

    function handler_permitSuperchainERC20(
        uint256 _fromPK,
        uint256 _callerActorIndex,
        uint256 _amount
    )
        public
        isInitialized
    {
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Mint tokens to the `fromEOA` address
        address fromEOA = vm.addr(_fromPK);
        SUPER_TOKEN.mint(fromEOA, _amount);

        // Sign the allowance from the `fromEOA` address to the `callerActor` address
        Actors callerActor = randomActor(_callerActorIndex);
        bytes32 domainSeparator = SUPER_TOKEN.DOMAIN_SEPARATOR();
        (uint8 v, bytes32 r, bytes32 s) =
            signPermit(_fromPK, address(callerActor), _amount, domainSeparator, nonces[fromEOA]);

        // Call permit
        try SUPER_TOKEN.permit(fromEOA, address(callerActor), _amount, block.timestamp, v, r, s) {
            assert(SUPER_TOKEN.allowance(fromEOA, address(callerActor)) == _amount);
            nonces[fromEOA]++;
        } catch {
            assert(false);
        }

        // Get callerActor's balance before
        uint256 callerActorBalanceBefore = SUPER_TOKEN.balanceOf(address(callerActor));

        // Call transferFrom
        try callerActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.transferFrom.selector, fromEOA, address(callerActor), _amount)
        ) {
            assert(SUPER_TOKEN.balanceOf(address(callerActor)) == callerActorBalanceBefore + _amount);
        } catch {
            assert(false);
        }
    }

    function handler_permit2SuperchainERC20(
        uint256 _fromActorIndex,
        address _spender,
        uint256 _amount
    )
        public
        isInitialized
    {
        // Get actor
        Actors fromActor = randomActor(_fromActorIndex);

        // Clamp the amount to prevent an insufficient balance revert
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(fromActor)));

        // Get callerActor's balance before
        uint256 callerActorBalanceBefore = SUPER_TOKEN.balanceOf(_spender);

        // Call mock permit to simulate the usage of Permit2 address to transfer the tokens
        try Permit2(Preinstalls.Permit2).permitTransferFrom(address(SUPER_TOKEN), address(fromActor), _spender, _amount)
        {
            if (_spender == address(fromActor)) {
                assert(SUPER_TOKEN.balanceOf(_spender) == callerActorBalanceBefore);
            } else {
                assert(SUPER_TOKEN.balanceOf(_spender) == callerActorBalanceBefore + _amount);
            }
        } catch {
            assert(false);
        }
    }

    function handler_depositSuperchainWETH(uint256 _value, uint256 _actorIndex) public isInitialized {
        _value = clampLte(_value, type(uint256).max - SUPER_WETH.totalSupply());

        Actors actor = randomActor(_actorIndex);
        vm.deal(address(actor), _value);

        try actor.directCall(address(SUPER_WETH), _value, abi.encodeWithSelector(SUPER_WETH.deposit.selector)) {
            _ghost_superWethBalancesSum += _value;
        } catch {
            assert(false);
        }
    }

    function handler_withdrawSuperchainWETH(uint256 _value, uint256 _actorIndex) public isInitialized {
        Actors actor = randomActor(_actorIndex);
        _value = clampLte(_value, SUPER_WETH.balanceOf(address(actor)));

        try actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.withdraw.selector, _value)
        ) {
            _ghost_superWethBalancesSum -= _value;
        } catch {
            assert(false);
        }
    }

    function handler_transferSuperchainWETH(address _to, uint256 _amount, uint256 _actorIndex) public isInitialized {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(actor)));

        try actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.transfer.selector, _to, _amount)
        ) { } catch {
            assert(false);
        }
    }

    function handler_transferFromSuperchainWETH(
        uint256 _fromActorIndex,
        uint256 _callerActorIndex,
        address _to,
        uint256 _amount
    )
        public
        isInitialized
    {
        Actors fromActor = randomActor(_fromActorIndex);
        Actors callerActor = randomActor(_callerActorIndex);
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(fromActor)));

        // Approve the spender to transfer the tokens
        try fromActor.directCall(
            address(SUPER_WETH),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_WETH.approve.selector, address(callerActor), _amount)
        ) { } catch {
            assert(false);
        }

        // Transfer the tokens
        try callerActor.directCall(
            address(SUPER_WETH),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_WETH.transferFrom.selector, address(fromActor), _to, _amount)
        ) { } catch {
            assert(false);
        }
    }

    function handler_permit2SuperchainWETH(
        uint256 _fromActorIndex,
        address _spender,
        uint256 _amount
    )
        public
        isInitialized
    {
        // Get actor
        Actors fromActor = randomActor(_fromActorIndex);

        // Clamp the amount to prevent an insufficient balance revert
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(fromActor)));

        // Get callerActor's balance before
        uint256 callerActorBalanceBefore = SUPER_WETH.balanceOf(_spender);

        // Call mock permit to simulate the usage of Permit2 address to transfer the tokens
        try Permit2(Preinstalls.Permit2).permitTransferFrom(address(SUPER_WETH), address(fromActor), _spender, _amount)
        {
            if (_spender == address(fromActor)) {
                assert(SUPER_WETH.balanceOf(_spender) == callerActorBalanceBefore);
            } else {
                assert(SUPER_WETH.balanceOf(_spender) == callerActorBalanceBefore + _amount);
            }
        } catch {
            assert(false);
        }
    }

    function handler_superchainWETHSendETH(
        address _to,
        uint256 _value,
        uint256 _chainId,
        uint256 _actorIndex
    )
        public
        isInitialized
    {
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
        isInitialized
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

    function signPermit(
        uint256 _fromPK,
        address _to,
        uint256 _amount,
        bytes32 _domainSeparator,
        uint256 _nonce
    )
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return vm.sign(
            _fromPK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _domainSeparator,
                    keccak256(abi.encode(PERMIT_TYPEHASH, vm.addr(_fromPK), _to, _amount, _nonce, block.timestamp))
                )
            )
        );
    }
}
