// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Constants, ConfigType, GameType, Predeploys } from "./Setup.sol";
import { Handler } from "./helpers/Handler.sol";
import { Utils } from "./utils/Utils.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { console } from "forge-std/Console.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Actors } from "./helpers/Actors.sol";

contract FuzzTest is Handler {
    using Utils for *;

    /// @custom:property-id 0
    /// @custom:property Check setup proper deployment and initialization of the contracts
    function property_setupSanityCheck() public isInitialized {
        /* Contracts with some storage intialization on setup */
        // Portal
        assert(PORTAL.proofMaturityDelaySeconds() == 1 weeks);
        assert(PORTAL.disputeGameFinalityDelaySeconds() == 3.5 days);
        assert(address(PORTAL.superchainConfig()) == superchainConfigAddress);
        assert(address(PORTAL.systemConfig()) == systemConfigAddress);
        assert(address(PORTAL.disputeGameFactory()) == _disputeGameFactory);

        // Shared Lockbox
        assert(address(SHARED_LOCKBOX.superchainConfig()) == superchainConfigAddress);

        // Superchain Config
        assert(address(SUPERCHAIN_CONFIG.sharedLockbox()) == sharedLockboxAddress);
        assert(SUPERCHAIN_CONFIG.guardian() == guardian);
        assert(SUPERCHAIN_CONFIG.paused() == false);
        assert(SUPERCHAIN_CONFIG.isInDependencySet(ORIGIN_CHAIN_ID));
        assert(SUPERCHAIN_CONFIG.authorizedPortals(optimismPortalAddress));

        // System Config
        uint256 systemConfigAStartBlock = SYSTEM_CONFIG.startBlock();
        assert(systemConfigAStartBlock > 0 && systemConfigAStartBlock <= block.number);
        assert(SYSTEM_CONFIG.basefeeScalar() == 0);
        assert(SYSTEM_CONFIG.blobbasefeeScalar() == 0);
        assert(SYSTEM_CONFIG.batcherHash() == 0x0000000000000000000000006887246668a3b87f54deb3b94ba47a6f63f32985);
        assert(SYSTEM_CONFIG.gasLimit() == 60000000);
        assert(SYSTEM_CONFIG.unsafeBlockSigner() == 0xAAAA45d9549EDA09E70937013520214382Ffc4A2);
        assert(SYSTEM_CONFIG.batchInbox() == 0xFF00000000000000000000000000000000000010);
        assert(SYSTEM_CONFIG.disputeGameFactory() == _disputeGameFactory);
        assert(SYSTEM_CONFIG.optimismPortal() == address(PORTAL));
        bytes memory resourceConfigA = abi.encode(SYSTEM_CONFIG.resourceConfig());
        bytes memory defaultResourceConfig = abi.encode(Constants.DEFAULT_RESOURCE_CONFIG());
        assert(resourceConfigA.hashBytes() == defaultResourceConfig.hashBytes());

        // SuperchainERC20
        string memory tokenName = "Super Token";
        string memory tokenSymbol = "SUP";
        assert(SUPER_TOKEN.name().hashString() == tokenName.hashString());
        assert(SUPER_TOKEN.symbol().hashString() == tokenSymbol.hashString());

        /* Contracts without any storage intialization on setup */
        // Check that it has a version, not checking which one to make the test more future proof
        string memory emptyString = "";
        bytes32 emptyStringHash = emptyString.hashString();
        assert(ETH_LIQUIDITY.version().hashString() != emptyStringHash);
        assert(L1_BLOCK.version().hashString() != emptyStringHash);
        assert(SUPER_WETH.version().hashString() != emptyStringHash);
        assert(L2_TO_L2_MESSENGER.version().hashString() != emptyStringHash);
        assert(SUPERCHAIN_TOKEN_BRIDGE.version().hashString() != emptyStringHash);
        assert(DEPENDENCY_MANAGER.version().hashString() != emptyStringHash);
    }

    /// @custom:property-id 1
    /// @custom:property Bridging SuperchainERC20s from the origin to destination decreases the token's totalSupply
    /// and the sender's balance on the origin chain by exactly the input amount.
    function test_sendSuperchainERC20(address _to, uint256 _amount) public isInitialized {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the chain id to a valid one
        // Set the amount to a valid one
        uint256 totalSupply = SUPER_TOKEN.totalSupply();
        _amount = clampLte(_amount, totalSupply);

        // Get state before call
        Actors actor = currentActor();
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(address(actor));
        uint256 sTokenTotalSupplyBefore = totalSupply;

        // Call the token bridge from the actor
        (bool success) = actor.callBridgeSendERC20(address(SUPER_TOKEN), _to, _amount, DESTINATION_CHAIN_ID);
        if (success) {
            assert(SUPER_TOKEN.balanceOf(address(actor)) == actorSTokenBalanceBefore - _amount);
            assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore - _amount);
        } else {
            assert(actorSTokenBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 2
    /// @custom:property Relaying SuperchainERC20s sent from origin increases the token's totalSupply and the
    /// target's balance on the destination chain by exactly the input amount
    function test_relaySuperchainERC20(
        Identifier memory _id,
        Message memory _message,
        uint256 _actorIndex
    )
        public
        isInitialized
    {
        _message.amount = clampLte(_message.amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);

        // Ensure the message is valid
        address targetActor = address(randomActor(_actorIndex));
        address messageTarget = address(SUPERCHAIN_TOKEN_BRIDGE);
        bytes memory message = abi.encodeCall(
            SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_TOKEN), _message.from, targetActor, _message.amount)
        );
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 sTokenTotalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(targetActor);

        // Relay the message by calling the messenger from the actor
        Actors actor = currentActor();
        (bool success) = actor.callL2ToL2MessengerRelayMessage(_id, sentMessage);

        if (success) {
            // Check the state is right after the call
            assert(SUPER_TOKEN.balanceOf(targetActor) == actorSTokenBalanceBefore + _message.amount);
            assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore + _message.amount);
            console.log("true");
            assert(false);
        } else {
            // If it fails, it should only be because the message was already relayed
            bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
                _destination: block.chainid,
                _source: _id.chainId,
                _nonce: _message.nonce,
                _sender: address(SUPERCHAIN_TOKEN_BRIDGE),
                _target: address(SUPERCHAIN_TOKEN_BRIDGE),
                _message: message
            });

            assertWithMsg(L2_TO_L2_MESSENGER.successfulMessages(messageHash), "Unknown Revert Error");
            console.log("false");
            assert(false);
        }
    }

    /// @custom:property-id 3
    /// @custom:property Bridging SuperchainWETH through SuperchainTokenBridge from origin to destination increases
    /// the ETHLiquidity Ether balance, and decreases the sender's SuperchainWETH balance on origin as well as
    /// SuperchainWETH total supply and Ether balance by exactly the input amount.
    function test_sendSuperchainWETH(address _to, uint256 _amount) public isInitialized {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the chain id to a valid one
        // Set the amount to a valid one
        uint256 totalSupply = SUPER_WETH.totalSupply();
        // TODO: Check if actually total sup and eth balance can differ and whether that should be an expected behavior
        _amount = clampLte(_amount, Utils.min(address(SUPER_WETH).balance, totalSupply));

        // Get state before call
        Actors actor = currentActor();
        uint256 actorSWethBalanceBefore = SUPER_WETH.balanceOf(address(actor));
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        // Call the token bridge from the actor
        (bool success) = actor.callBridgeSendERC20(address(SUPER_WETH), _to, _amount, DESTINATION_CHAIN_ID);
        if (success) {
            _ghost_superWethBalancesSum -= _amount;

            assert(SUPER_WETH.balanceOf(address(actor)) == actorSWethBalanceBefore - _amount);
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore + _amount);
            assert(address(SUPER_WETH).balance == sWethEthBalanceBefore - _amount);
            assert(SUPER_WETH.totalSupply() == totalSupply - _amount);
        } else {
            assert(actorSWethBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 4
    /// @custom:property Relaying SuperchainWETH sent from origin through SuperchainTokenBridge on destination
    /// decreases the ETHLiquidity Ether balance, and increases the target’s SuperchainWETH balance on destination as
    /// well as SuperchainWETH total supply and Ether balance by exactly the input amount.
    function test_relaySuperchainWETH(
        Identifier memory _id,
        Message memory _message,
        uint256 _actorIndex
    )
        public
        isInitialized
    {
        // To avoid a revert, the amount must be lesser than the ETHLiquidity ether balance (insufficient ether) and
        // lesser than the max uint256 less the SuperchainWETH total supply (overflow)
        uint256 totalSupplyBefore = SUPER_WETH.totalSupply();
        _message.amount =
            clampLte(_message.amount, Utils.min(address(ETH_LIQUIDITY).balance, type(uint256).max - totalSupplyBefore));

        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);

        // Ensure the message is valid
        address targetActor = address(randomActor(_actorIndex));
        address messageTarget = address(SUPERCHAIN_TOKEN_BRIDGE);
        bytes memory message = abi.encodeCall(
            SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_WETH), _message.from, targetActor, _message.amount)
        );
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 actorSWethBalanceBefore = SUPER_WETH.balanceOf(targetActor);
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        // Relay the message by calling the messenger from the actor
        Actors actor = currentActor();
        (bool success) = actor.callL2ToL2MessengerRelayMessage(_id, sentMessage);

        if (success) {
            _ghost_superWethBalancesSum += _message.amount;

            assert(SUPER_WETH.balanceOf(targetActor) == actorSWethBalanceBefore + _message.amount);
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore - _message.amount);
            assert(address(SUPER_WETH).balance == sWethEthBalanceBefore + _message.amount);
            assert(SUPER_WETH.totalSupply() == totalSupplyBefore + _message.amount);
        } else {
            // If it fails, it should only be because the message was already relayed
            bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
                _destination: block.chainid,
                _source: _id.chainId,
                _nonce: _message.nonce,
                _sender: address(SUPERCHAIN_TOKEN_BRIDGE),
                _target: messageTarget,
                _message: message
            });

            assertWithMsg(L2_TO_L2_MESSENGER.successfulMessages(messageHash), "Unknown Revert Error");
        }
    }

    /// @custom:property-id 8
    /// @custom:property ETHLiquidity#mint() MUST never be callable such that its balance would decrease below 0
    function test_mintSuperchainWETH(
        Identifier memory _id,
        Message memory _message,
        address _target,
        bool _callSuperWETH
    )
        public
        isInitialized
    {
        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);

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
        bool success = currentActor().callL2ToL2MessengerRelayMessage(_id, sentMessage);

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

    /// @custom:property-id 9
    /// @custom:property ETHLiquidity#burn() MUST never be callable such that its balance would increase beyond
    /// `type(uint256).max
    function test_burnSuperchainWETH(address _to, uint256 _amount, bool _callSuperWETH) public isInitialized {
        _to = clampGt(_to, address(0));

        // Get state before call
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;

        bool success;
        if (_callSuperWETH) {
            _amount = clampLte(_amount, Utils.min(address(currentActor()).balance, address(SUPER_WETH).balance));
            success = currentActor().callSuperchainWETHSendETH{ value: _amount }(_to, DESTINATION_CHAIN_ID);
        } else {
            _amount =
                clampLte(_amount, Utils.min(SUPER_WETH.balanceOf(address(currentActor())), address(SUPER_WETH).balance));
            success = currentActor().callBridgeSendERC20(address(SUPER_WETH), _to, _amount, DESTINATION_CHAIN_ID);
        }

        if (success) {
            if (!_callSuperWETH) _ghost_superWethBalancesSum -= _amount;
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore + _amount);
        } else {
            // Check overflow in ETHLiquidity
            assert(address(ETH_LIQUIDITY).balance > type(uint256).max - _amount);
        }
    }

    /// @custom:property-id 14
    /// @custom:property The total sum of SuperchainWETH user balances MUST be equal or less to the total supply
    function test_superWETHSupplyEqualsBalances() public isInitialized {
        // The user balances sum should be equal to the total supply less the Ether relayed or sent to SuperWETH
        assert(_ghost_superWethBalancesSum == SUPER_WETH.totalSupply() - _ghost_superWethEtherSent);
    }
}
