// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Constants, GameType, Predeploys } from "./Setup.sol";
import { Handler } from "./helpers/Handler.sol";
import { Utils } from "./utils/Utils.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Actors, ICrossL2InboxWithSlotWarming } from "./helpers/Actors.sol";
import { Types } from "src/libraries/Types.sol";
import { vm } from "./utils/VM.sol";
import { IOptimismPortalMock } from "./interfaces/IOptimismPortalMock.sol";
import { WeirdTarget } from "./mocks/WeirdTarget.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";

contract FuzzTest is Handler {
    uint64 internal constant _WITHDRAWAL_GAS_OVERHEAD = 285_000;
    uint256 internal constant _DATA_LENGTH_MAX_LIMIT = 120_000;

    // TODO: Move to a helper function
    struct CallRelayParams {
        Identifier id;
        bytes messageSent;
        bytes message;
        uint256 nonce;
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

    /// @custom:property-id 1
    /// @custom:property Bridging SuperchainERC20s from the origin to destination decreases the token's totalSupply
    /// and the sender's balance on the origin chain by exactly the input amount.
    function test_sendSuperchainERC20(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the chain id to a valid one
        // Set the amount to a valid one
        uint256 totalSupply = SUPER_TOKEN.totalSupply();
        _amount = clampLte(_amount, totalSupply);

        // Get state before call
        address actor = address(randomActor(_actorIndex));
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(actor);
        uint256 sTokenTotalSupplyBefore = totalSupply;

        // Call the token bridge
        vm.prank(actor);
        try ISuperchainTokenBridge(SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
            address(SUPER_TOKEN), _to, _amount, DESTINATION_CHAIN_ID
        ) {
            assert(SUPER_TOKEN.balanceOf(actor) == actorSTokenBalanceBefore - _amount);
            assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore - _amount);
        } catch {
            assert(actorSTokenBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 2
    /// @custom:property Relaying SuperchainERC20s sent from origin increases the token's totalSupply and the
    /// target's balance on the destination chain by exactly the input amount
    function test_relaySuperchainERC20(
        Identifier memory _id,
        Message memory _message,
        address _sender,
        address _target
    )
        public
        initialize
    {
        require(!_isL1Contract(_target));
        _message.amount = clampLte(_message.amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        _id.blockNumber = clampLte(_id.blockNumber, type(uint64).max);
        _id.logIndex = clampLte(_id.logIndex, type(uint32).max);
        _id.timestamp = clampLte(_id.timestamp, type(uint64).max);

        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);

        // Ensure the message is valid
        address messageTarget = address(SUPERCHAIN_TOKEN_BRIDGE);
        bytes memory message = abi.encodeCall(
            SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_TOKEN), _message.from, _target, _message.amount)
        );
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 sTokenTotalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(_target);

        // Relay the message by calling the messenger
        (bool success, bytes32 messageHash) = _callL2ToL2MessengerRelayMessage(
            _sender, CallRelayParams({ id: _id, messageSent: sentMessage, message: message, nonce: _message.nonce })
        );

        // Assert
        if (success) {
            // Check the state is right after the call
            assert(SUPER_TOKEN.balanceOf(_target) == actorSTokenBalanceBefore + _message.amount);
            assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore + _message.amount);
        } else {
            // Ensure the message was already relayed
            assert(L2_TO_L2_MESSENGER.successfulMessages(messageHash));
        }
    }

    /// @custom:property-id 3
    /// @custom:property Bridging SuperchainWETH through SuperchainTokenBridge from origin to destination increases
    /// the ETHLiquidity Ether balance, and decreases the sender's SuperchainWETH balance on origin as well as
    /// SuperchainWETH total supply and Ether balance by exactly the input amount.
    function test_sendSuperchainWETH(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the amount to a valid one
        uint256 totalSupply = SUPER_WETH.totalSupply();
        _amount = clampLte(_amount, totalSupply);

        // Get state before call
        address actor = address(randomActor(_actorIndex));
        uint256 senderSWethBalanceBefore = SUPER_WETH.balanceOf(actor);
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        // Call the token bridge
        vm.prank(actor);
        try ISuperchainTokenBridge(SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
            address(SUPER_WETH), _to, _amount, DESTINATION_CHAIN_ID
        ) {
            _ghost_superWethBalancesSum -= _amount;

            assert(SUPER_WETH.balanceOf(actor) == senderSWethBalanceBefore - _amount);
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore + _amount);
            assert(address(SUPER_WETH).balance == sWethEthBalanceBefore - _amount);
            assert(SUPER_WETH.totalSupply() == totalSupply - _amount);
        } catch {
            assert(senderSWethBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 4
    /// @custom:property Relaying SuperchainWETH sent from origin through SuperchainTokenBridge on destination
    /// decreases the ETHLiquidity Ether balance, and increases the target’s SuperchainWETH balance on destination as
    /// well as SuperchainWETH total supply and Ether balance by exactly the input amount.
    function test_relaySuperchainWETH(
        Identifier memory _id,
        Message memory _message,
        address _sender,
        address _target
    )
        public
        initialize
    {
        // To avoid a revert, the amount must be lesser than the ETHLiquidity ether balance (insufficient ether) and
        // lesser than the max uint256 less the SuperchainWETH total supply (overflow)
        uint256 totalSupplyBefore = SUPER_WETH.totalSupply();

        // Ensure the amount is valid
        _message.amount =
            clampLte(_message.amount, Utils.min(address(ETH_LIQUIDITY).balance, type(uint256).max - totalSupplyBefore));

        // Ensure the message is valid
        bytes memory message = abi.encodeCall(
            SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_WETH), _message.from, _target, _message.amount)
        );
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, address(SUPERCHAIN_TOKEN_BRIDGE), _message.nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 targetSWethBalanceBefore = SUPER_WETH.balanceOf(_target);
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        // Relay the message by calling the messenger from the actor
        CallRelayParams memory callRelayParams =
            CallRelayParams({ id: _id, messageSent: sentMessage, message: message, nonce: _message.nonce });
        (bool success, bytes32 messageHash) = _callL2ToL2MessengerRelayMessage(_sender, callRelayParams);

        if (success) {
            _ghost_superWethBalancesSum += _message.amount;

            assert(SUPER_WETH.balanceOf(_target) == targetSWethBalanceBefore + _message.amount);
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore - _message.amount);
            assert(address(SUPER_WETH).balance == sWethEthBalanceBefore + _message.amount);
            assert(SUPER_WETH.totalSupply() == totalSupplyBefore + _message.amount);
        } else {
            // If it fails, it should only be because the message was already relayed
            assertWithMsg(L2_TO_L2_MESSENGER.successfulMessages(messageHash), "Unknown Revert Error");
        }
    }

    /// @custom:property-id 6
    /// @custom:property ETHLiquidity#mint() MUST never be callable such that its balance would decrease below 0
    function test_mintSuperchainWETH(
        Identifier memory _id,
        Message memory _message,
        address _sender,
        address _target,
        bool _callSuperWETH
    )
        public
        initialize
    {
        require(!_isL1Contract(_target));

        bytes memory message;
        bytes memory sentMessage;

        // Select minting path: SuperchainWETH or SupertokenBridge
        if (_callSuperWETH) {
            _message.amount = clampLte(_message.amount, type(uint256).max - address(SUPER_WETH).balance);
            message = abi.encodeCall(SUPER_WETH.relayETH, (_message.from, _target, _message.amount));
            sentMessage = abi.encodePacked(
                abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, address(SUPER_WETH), _message.nonce), // topics
                abi.encode(address(SUPER_WETH), message) // data
            );
        } else {
            _message.amount = clampLte(_message.amount, type(uint256).max - SUPER_WETH.totalSupply());
            message = abi.encodeCall(
                SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_WETH), _message.from, _target, _message.amount)
            );
            sentMessage = abi.encodePacked(
                abi.encode(
                    _SENT_MESSAGE_EVENT_SELECTOR, block.chainid, address(SUPERCHAIN_TOKEN_BRIDGE), _message.nonce
                ), // topics
                abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
            );
        }

        // Ensure the message is not already relayed
        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: block.chainid,
            _source: _id.chainId,
            _nonce: _message.nonce,
            _sender: _callSuperWETH ? address(SUPER_WETH) : address(SUPERCHAIN_TOKEN_BRIDGE),
            _target: _callSuperWETH ? address(SUPER_WETH) : address(SUPERCHAIN_TOKEN_BRIDGE),
            _message: message
        });
        require(!L2_TO_L2_MESSENGER.successfulMessages(messageHash));

        // Get state before call
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;

        // Relay the message
        (bool success,) = _callL2ToL2MessengerRelayMessage(
            _sender, CallRelayParams({ id: _id, messageSent: sentMessage, message: message, nonce: _message.nonce })
        );

        if (success) {
            // If the relay target was SuperchainWETH, the total supply should be updated, independently of the tx
            // path
            if (_callSuperWETH && _target == address(SUPER_WETH)) _ghost_superWethEtherSent += _message.amount;
            // Otherwise, only if it was minted through `crosschainMint()`, the total supply should be updated
            else if (!_callSuperWETH) _ghost_superWethBalancesSum += _message.amount;

            // If the tx path was `relayETH` and the target was ETHLiquidity, the balance should be the same
            if (_callSuperWETH && _target == address(ETH_LIQUIDITY)) {
                assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore);
            } else {
                // Balance should be the same independently of the tx path, as long as the target is not ETHLiquidity
                assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore - _message.amount);
            }
        } else {
            // Check underflow in ETHLiquidity
            assert(ethLiquidityEthBalanceBefore < _message.amount);
        }
    }

    /// @custom:property-id 7
    /// @custom:property ETHLiquidity#burn() MUST never be callable such that its balance would increase beyond
    /// `type(uint256).max
    function test_burnSuperchainWETH(address _to, uint256 _amount, bool _callSuperWETH) public initialize {
        if (_to == address(0)) _to = address(type(uint160).max);

        // Get state before call
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;

        address actor = address(currentActor());
        bool success;
        if (_callSuperWETH) {
            _amount = clampLte(_amount, Utils.min(actor.balance, address(SUPER_WETH).balance));

            // vm.prank(actor);
            // (success,) = address(SUPER_WETH).call{ value: _amount }(
            //     abi.encodeWithSelector(ISuperchainWETH.sendETH.selector, _to, DESTINATION_CHAIN_ID)
            // );

            /// NOTE: `vm.prank` is not working here, so we use `directCall` instead
            (success,) = Actors(payable(actor)).directCall(
                address(SUPER_WETH),
                _amount,
                abi.encodeWithSelector(ISuperchainWETH.sendETH.selector, _to, DESTINATION_CHAIN_ID)
            );
        } else {
            _amount = clampLte(_amount, Utils.min(SUPER_WETH.balanceOf(actor), address(SUPER_WETH).balance));

            vm.prank(actor);
            (success,) = address(SUPERCHAIN_TOKEN_BRIDGE).call(
                abi.encodeWithSelector(
                    ISuperchainTokenBridge.sendERC20.selector, address(SUPER_WETH), _to, _amount, DESTINATION_CHAIN_ID
                )
            );
        }

        if (success) {
            if (!_callSuperWETH) _ghost_superWethBalancesSum -= _amount;
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore + _amount);
        } else {
            // Check overflow in ETHLiquidity
            assert(address(ETH_LIQUIDITY).balance > type(uint256).max - _amount);
        }
    }

    /// @custom:property-id 8
    /// @custom:property The total sum of SuperchainWETH user balances MUST be equal or less to the total supply
    function test_superWETHSupplyEqualsBalances() public initialize {
        // The user balances sum should be equal to the total supply less the Ether relayed or sent to SuperWETH
        assert(_ghost_superWethBalancesSum == SUPER_WETH.totalSupply() - _ghost_superWethEtherSent);
    }

    /// @custom:property-id 10
    /// @custom:property OptimismPortals MUST lock the ETH amount on the ETHLockbox when on a
    /// deposit transaction with value greater than zero, without holding any ETH balance from
    /// the depositing users.
    function test_optimismPortalDeposits(
        address _to,
        uint256 _value,
        bool _isCreation,
        bytes memory _data
    )
        public
        initialize
    {
        // Avoid revert due to `BadTarget`
        require(!(_isCreation && _to != address(0)));

        // Avoid revert due to `LargeCalldata`
        require(_data.length <= _DATA_LENGTH_MAX_LIMIT);

        // Get the gas limit for the deposit transaction to succeed
        uint64 gasLimit = uint64(_WITHDRAWAL_GAS_OVERHEAD + (_data.length * 16) * 64 / 63);

        Actors actor = randomActor(_value);
        _value = clampLte(_value, address(actor).balance);
        uint256 balanceBefore = address(ETH_LOCKBOX).balance;

        // Deposit the transaction
        /// NOTE: `vm.prank` is not working here, so we use `directCall` instead
        (bool success,) = actor.directCall(
            address(PORTAL),
            _value,
            abi.encodeCall(PORTAL.depositTransaction, (_to, _value, gasLimit, _isCreation, _data))
        );
        assert(success);

        assert(address(ETH_LOCKBOX).balance == balanceBefore + _value);
    }

    /// @custom:property-id 11
    /// @custom:property OptimismPortals MUST unlock the ETH amount being withdrawn from the
    /// ETHLockbox if it is greater than zero.
    function test_optimismPortalWithdrawals(
        Types.WithdrawalTransaction memory _tx,
        uint256 _actorIndex
    )
        public
        initialize
    {
        require(_tx.target != address(PORTAL));
        require(_tx.target != address(ETH_LOCKBOX));
        require(!_isL2Contract(_tx.target));

        // Setting not used parameters to empty values
        bytes[] memory withdrawalProof = new bytes[](0);
        Types.OutputRootProof memory outputRootProof;
        uint256 disputeGameIndex = 0;

        // Gas is limit is out of scope
        _tx.gasLimit = type(uint256).max;

        _tx.value = clampLte(_tx.value, address(ETH_LOCKBOX).balance);

        // Ensure the withdrawal was not already finalized
        require(!PORTAL.finalizedWithdrawals(Hashing.hashWithdrawal(_tx)));

        uint256 portalBalanceBefore = address(PORTAL).balance;
        uint256 ethLockboxBalanceBefore = address(ETH_LOCKBOX).balance;

        Actors actor = randomActor(_actorIndex);

        vm.prank(address(actor));
        try PORTAL.proveWithdrawalTransaction(_tx, disputeGameIndex, outputRootProof, withdrawalProof) {
            vm.warp(block.timestamp + PROOF_MATURITY_DELAY_SECONDS + 1);
        } catch {
            assert(false);
        }

        vm.prank(address(actor));
        try IOptimismPortalMock(address(PORTAL)).finalizeWithdrawalTransaction(_tx) returns (bool success) {
            // If the safecall was successful, the balance should be decreased by the amount of the withdrawal
            if (success) {
                if (_tx.value == 0) assert(address(ETH_LOCKBOX).balance == ethLockboxBalanceBefore);
                else assert(address(ETH_LOCKBOX).balance == ethLockboxBalanceBefore - _tx.value);
            } else {
                assert(address(ETH_LOCKBOX).balance == ethLockboxBalanceBefore - _tx.value);
                assert(address(PORTAL).balance == portalBalanceBefore + _tx.value);
            }
        } catch {
            // Make sure the finalize call doesn't revert.
            assert(false);
        }
    }

    /// @custom:property-id 12
    /// @custom:property `OptimismPortal`s `unlockETH` MUST NOT be called on a finalized withdrawal transaction
    ///                   context
    function test_noETHUnlockedDuringWithdrawal(
        address _caller,
        Types.WithdrawalTransaction memory _tx
    )
        public
        initialize
    {
        _tx.value = clampLte(_tx.value, address(ETH_LOCKBOX).balance);
        // Set the target to the WeirdTarget and the data to the selector of the function that will be called.
        _tx.target = address(WEIRD_TARGET);
        _tx.data = abi.encodeWithSelector(WeirdTarget.callLockboxUnlockETH.selector);

        vm.prank(address(_caller));
        bool success = IOptimismPortalMock(address(PORTAL)).finalizeWithdrawalTransaction(_tx);
        assert(!success);
    }

    /// @notice Unguided test that doesn't match any specific property, but checks that withdrawal finalization
    ///         checks are correct by making a malicious call on a target contract.
    function test_finalizeWithdrawalReverts_unguided(
        address _caller,
        Types.WithdrawalTransaction memory _tx,
        uint256 _callIndex,
        uint256 _actorIndex
    )
        public
        initialize
    {
        // Get the call to be made.
        bytes4 call = WEIRD_TARGET.calls(_callIndex % _ghost_weirdTargetCallsLength);

        _tx.value = clampLte(_tx.value, address(ETH_LOCKBOX).balance);
        _tx.target = address(WEIRD_TARGET);
        _tx.data = abi.encodeWithSelector(call);
        // Gas is limit is out of scope
        _tx.gasLimit = type(uint256).max;

        // Setting not used parameters to empty values
        bytes[] memory withdrawalProof = new bytes[](0);
        Types.OutputRootProof memory outputRootProof;
        uint256 disputeGameIndex = 0;

        // Prove the withdrawal transaction.
        vm.prank(_caller);
        try IOptimismPortalMock(address(PORTAL)).proveWithdrawalTransaction(
            _tx, disputeGameIndex, outputRootProof, withdrawalProof
        ) { } catch {
            // Make sure the call doesn't revert.
            assert(false);
        }

        // Finalize the withdrawal transaction.
        vm.warp(block.timestamp + PROOF_MATURITY_DELAY_SECONDS + 1);
        vm.prank(_caller);
        try IOptimismPortalMock(address(PORTAL)).finalizeWithdrawalTransaction(_tx) returns (bool success) {
            // Ensure the WeirdTarget call reverts.
            assert(!success);
        } catch {
            // Make sure the finalize call doesn't revert.
            assert(false);
        }
    }
}
