// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    Setup,
    Preinstalls,
    Constants,
    Predeploys,
    IDisputeGameFactory,
    ISystemConfig,
    ISuperchainConfig,
    GameType
} from "../Setup.sol";
import { Actors } from "./Actors.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Permit2Mock as Permit2 } from "../mocks/Permit2Mock.sol";
import { Utils } from "../utils/Utils.sol";
import { vm } from "../utils/VM.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { StorageSetter } from "src/universal/StorageSetter.sol";
import { SafeSend } from "src/universal/SafeSend.sol";
import { OptimismPortal2 as OptimismPortal } from "src/L1/OptimismPortal2.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

contract Handler is Setup {
    struct Message {
        address from;
        uint256 amount;
        uint256 nonce;
    }

    struct CallRelayParams {
        Identifier id;
        bytes messageSent;
        bytes message;
        uint256 nonce;
    }

    /// @notice Event selector for the SentMessage event.
    bytes32 internal constant _SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    uint256 internal constant _ZERO_VALUE = 0;

    mapping(address => uint256) public nonces;

    /// NOTE: Using this modifier because the initialization is not working when called inside the constructor on medusa
    modifier initialize() {
        if (!_ghost_isInitialized) {
            _initializeProxies();
            _setupSanityCheck();
            _ghost_isInitialized = true;
        }
        _;
    }

    /// @notice Helper to bypass the access list checksum validation on `CrossL2Inbox`
    function _callL2ToL2MessengerRelayMessage(
        address _sender,
        CallRelayParams memory _params
    )
        internal
        returns (bool _success, bytes32 messageHash)
    {
        // Ensure the inputs types are valid
        _params.id.blockNumber = clampLte(_params.id.blockNumber, type(uint64).max);
        _params.id.logIndex = clampLte(_params.id.logIndex, type(uint32).max);
        _params.id.timestamp = clampLte(_params.id.timestamp, type(uint64).max);
        _params.id.origin = address(L2_TO_L2_MESSENGER);

        // hash the message
        messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: block.chainid,
            _source: _params.id.chainId,
            _nonce: _params.nonce,
            _sender: address(SUPERCHAIN_TOKEN_BRIDGE),
            _target: address(SUPERCHAIN_TOKEN_BRIDGE),
            _message: abi.encode(_params.message)
        });

        // calculate the checksum
        bytes32 slot = CROSS_L2_INBOX.calculateChecksum(_params.id, keccak256(_params.messageSent));

        // warm the slot
        CROSS_L2_INBOX.warmSlot(slot);

        // Relay the message
        vm.prank(_sender);
        (_success,) = address(L2_TO_L2_MESSENGER).call(
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.relayMessage.selector, _params.id, _params.messageSent)
        );
    }

    function handler_transferSuperchainERC20(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(actor)));

        vm.prank(address(actor));
        try SUPER_TOKEN.transfer(_to, _amount) { }
        catch {
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
        initialize
    {
        Actors fromActor = randomActor(_fromActorIndex);
        Actors callerActor = randomActor(_callerActorIndex);
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(fromActor)));

        // Approve the spender to transfer the tokens
        vm.prank(address(fromActor));
        try SUPER_TOKEN.approve(address(callerActor), _amount) { }
        catch {
            assert(false);
        }

        // Transfer the tokens
        vm.prank(address(callerActor));
        try SUPER_TOKEN.transferFrom(address(fromActor), _to, _amount) { }
        catch {
            assert(false);
        }
    }

    function handler_permitSuperchainERC20(
        uint256 _fromPK,
        uint256 _callerActorIndex,
        uint256 _amount
    )
        public
        initialize
    {
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Mint tokens to the `fromEOA` address
        address fromEOA = vm.addr(_fromPK);
        SUPER_TOKEN.mint(fromEOA, _amount);

        // Sign the allowance from the `fromEOA` address to the `callerActor` address
        Actors callerActor = randomActor(_callerActorIndex);
        bytes32 domainSeparator = SUPER_TOKEN.DOMAIN_SEPARATOR();
        (uint8 v, bytes32 r, bytes32 s) =
            Utils._signPermit(_fromPK, address(callerActor), _amount, domainSeparator, nonces[fromEOA]);

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
        vm.prank(address(callerActor));
        try SUPER_TOKEN.transferFrom(fromEOA, address(callerActor), _amount) {
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
        initialize
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

    function handler_depositSuperchainWETH(uint256 _value, uint256 _actorIndex) public initialize {
        _value = clampLte(_value, type(uint256).max - SUPER_WETH.totalSupply());

        Actors actor = randomActor(_actorIndex);
        vm.deal(address(actor), _value);

        (bool success,) =
            actor.directCall(address(SUPER_WETH), _value, abi.encodeWithSelector(SUPER_WETH.deposit.selector));
        assert(success);

        _ghost_superWethBalancesSum += _value;
    }

    function handler_withdrawSuperchainWETH(uint256 _value, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _value = clampLte(_value, SUPER_WETH.balanceOf(address(actor)));

        vm.prank(address(actor));
        try SUPER_WETH.withdraw(_value) {
            _ghost_superWethBalancesSum -= _value;
        } catch {
            assert(false);
        }
    }

    function handler_transferSuperchainWETH(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(actor)));

        vm.prank(address(actor));
        try SUPER_WETH.transfer(_to, _amount) { }
        catch {
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
        initialize
    {
        Actors fromActor = randomActor(_fromActorIndex);
        Actors callerActor = randomActor(_callerActorIndex);
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(fromActor)));

        // Approve the spender to transfer the tokens
        vm.prank(address(fromActor));
        try SUPER_WETH.approve(address(callerActor), _amount) { }
        catch {
            assert(false);
        }

        // Transfer the tokens
        vm.prank(address(callerActor));
        try SUPER_WETH.transferFrom(address(fromActor), _to, _amount) { }
        catch {
            assert(false);
        }
    }

    function handler_permit2SuperchainWETH(
        uint256 _fromActorIndex,
        address _spender,
        uint256 _amount
    )
        public
        initialize
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

    function handler_superchainWETHSendETH(address _to, uint256 _value, uint256 _actorIndex) public initialize {
        require(_to != address(0));

        // Get state before call
        Actors actor = randomActor(_actorIndex);
        uint256 actorBalanceBefore = actor.ethBalance();
        uint256 sWethBalanceBefore = address(SUPER_WETH).balance;
        uint256 _ethLiquidityBefore = address(ETH_LIQUIDITY).balance;
        uint256 _sWETHTotalSupplyBefore = SUPER_WETH.totalSupply();

        // Clamp the value to prevent an overflow or a revert due to insufficient balance
        _value = clampLte(_value, Utils.min(type(uint256).max - sWethBalanceBefore, actorBalanceBefore));

        (bool success,) = actor.directCall(
            address(SUPER_WETH), _value, abi.encodeCall(SUPER_WETH.sendETH, (_to, DESTINATION_CHAIN_ID))
        );
        assert(success);

        // Check the Ether balances and that the superchain WETH total supply was not modified
        assert(actor.ethBalance() == actorBalanceBefore - _value);
        assert(address(ETH_LIQUIDITY).balance == _ethLiquidityBefore + _value);
        // The total supply of superchain WETH should not change
        assert(SUPER_WETH.totalSupply() == _sWETHTotalSupplyBefore);
    }

    function handler_superchainWETHRelayETH(
        Identifier memory _id,
        Message memory _message,
        uint256 _toActorIndex
    )
        public
        initialize
    {
        // Ensure the id inputs are valid
        _id.origin = address(L2_TO_L2_MESSENGER);
        _message.amount = clampLte(_message.amount, address(ETH_LIQUIDITY).balance - address(SUPER_WETH).balance);

        _id.blockNumber = clampLte(_id.blockNumber, type(uint64).max);
        _id.logIndex = clampLte(_id.logIndex, type(uint32).max);
        _id.timestamp = clampLte(_id.timestamp, type(uint64).max);

        // Get state before the call
        address targetActor = address(randomActor(_toActorIndex));
        uint256 _tagretActorBalanceBefore = targetActor.balance;
        uint256 _ethLiquidityBefore = address(ETH_LIQUIDITY).balance;
        uint256 _sWETHTotalSupplyBefore = SUPER_WETH.totalSupply();

        // Build the message
        address messageTarget = address(SUPER_WETH);
        bytes memory message = abi.encodeCall(SUPER_WETH.relayETH, (_message.from, targetActor, _message.amount));
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(SUPER_WETH), message) // data
        );

        // Relay the message
        (bool success, bytes32 messageHash) = _callL2ToL2MessengerRelayMessage(
            address(randomActor(_toActorIndex + 1)),
            CallRelayParams({ id: _id, messageSent: sentMessage, message: message, nonce: _message.nonce })
        );

        // Check the Ether balances
        if (success) {
            assert(address(ETH_LIQUIDITY).balance == _ethLiquidityBefore - _message.amount);
            assert(targetActor.balance == _tagretActorBalanceBefore + _message.amount);
            // The total supply of superchain WETH should not change
            assert(SUPER_WETH.totalSupply() == _sWETHTotalSupplyBefore);
        } else {
            // If it fails, it should only be because the message was already relayed
            assert(L2_TO_L2_MESSENGER.successfulMessages(messageHash));
        }
    }

    // Increases the block number, needed to avoid hitting the L2 block gas limit while depositing on the OptimismPortal
    function handler_increaseBlockNumber(bool _increaseTwo) public initialize {
        // Increase the block number by 2 if the _increaseTwo flag is true, otherwise increase it by 1 to handle
        // different block gas limits on ResourceMetering.sol
        uint256 blocks = _increaseTwo ? 2 : 1;
        vm.roll(block.number + blocks);
    }

    function handler_donateETH(uint256 _amount, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, actor.ethBalance());

        // Get balances before
        uint256 actorBalanceBefore = actor.ethBalance();
        uint256 portalBalanceBefore = address(PORTAL).balance;

        (bool success,) = actor.directCall(address(PORTAL), _amount, abi.encodeWithSelector(PORTAL.donateETH.selector));
        assert(success);
        assert(actor.ethBalance() == actorBalanceBefore - _amount);
        assert(address(PORTAL).balance == portalBalanceBefore + _amount);
    }

    /// @notice This function is used to send ether to the random addresses. To check how balance changes affect the
    /// behavior of contracts.
    function handler_safeSendETH(address payable _to, uint256 _amount) public initialize {
        // Clamp the amount to prevent an overflow
        _amount = clampBetween(_amount, 0, Utils.min(type(uint256).max - _to.balance, 10 ether));
        // Since the Medusa.callSequenceLength is set 50, the max amount of ether that can be sent is 50 * 10 ether.
        vm.deal(address(this), _amount);
        new SafeSend{ value: _amount }(_to);

        if (_to == address(SUPER_WETH)) _ghost_superWethEtherSent += _amount;
    }
}
