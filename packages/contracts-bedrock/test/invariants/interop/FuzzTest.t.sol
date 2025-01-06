// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Constants, ConfigType, GameType, Predeploys } from "./Setup.sol";
import { Handler } from "./Handler.t.sol";
import { Helpers } from "./utils/Helpers.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { console } from "forge-std/Console.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";

contract FuzzTest is Handler {
    using Helpers for *;

    struct Message {
        address from;
        uint256 amount;
        uint256 nonce;
    }

    /// @notice Event selector for the SentMessage event.
    bytes32 internal constant _SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    bool initialized;

    /// NOTE: Using this modifier because the initialization is not working when called inside the constructor on medusa
    modifier isInitialized() {
        if (!initialized) {
            _initializeEverything();
            initialized = true;
        }
        _;
    }

    // TODO: Move it to be an internal function inside the constructor
    /// @notice Tests the contracts vars are set up correctly
    function test_setup() public isInitialized {
        /* Contracts with some storage intialization on setup */
        // Portal
        assert(PORTAL.proofMaturityDelaySeconds() == 1 weeks);
        assert(PORTAL.disputeGameFinalityDelaySeconds() == 3.5 days);
        assert(address(PORTAL.systemConfig()) == systemConfigAddress);
        assert(address(PORTAL.superchainConfig()) == superchainConfigAddress);
        assert(address(PORTAL.disputeGameFactory()) == _disputeGameFactory);

        // Shared Lockbox
        assert(address(SHARED_LOCKBOX.SUPERCHAIN_CONFIG()) == superchainConfigAddress);

        // Superchain Config
        assert(address(SUPERCHAIN_CONFIG.SHARED_LOCKBOX()) == sharedLockboxAddress);
        assert(SUPERCHAIN_CONFIG.guardian() == guardian);
        assert(SUPERCHAIN_CONFIG.dependencyManager() == dependencyManager);
        assert(SUPERCHAIN_CONFIG.paused() == false);

        // System Config
        uint256 sysConfigStartBlock = SYSTEM_CONFIG.startBlock();
        assert(sysConfigStartBlock > 0 && sysConfigStartBlock <= block.number);
        assert(SYSTEM_CONFIG.basefeeScalar() == 0);
        assert(SYSTEM_CONFIG.blobbasefeeScalar() == 0);
        assert(SYSTEM_CONFIG.batcherHash() == 0x0000000000000000000000006887246668a3b87f54deb3b94ba47a6f63f32985);
        assert(SYSTEM_CONFIG.gasLimit() == 60000000);
        assert(SYSTEM_CONFIG.unsafeBlockSigner() == 0xAAAA45d9549EDA09E70937013520214382Ffc4A2);
        assert(SYSTEM_CONFIG.batchInbox() == 0xFF00000000000000000000000000000000000010);
        assert(SYSTEM_CONFIG.disputeGameFactory() == _disputeGameFactory);
        assert(SYSTEM_CONFIG.optimismPortal() == address(PORTAL));
        (address gasPayingToken,) = SYSTEM_CONFIG.gasPayingToken();
        assert(gasPayingToken == Constants.ETHER);
        bytes memory resourceConfig = abi.encode(SYSTEM_CONFIG.resourceConfig());
        bytes memory defaultResourceConfig = abi.encode(Constants.DEFAULT_RESOURCE_CONFIG());
        assert(resourceConfig.hashBytes() == defaultResourceConfig.hashBytes());

        // SuperchainERC20
        string memory tokenName = "Super Token";
        string memory tokenSymbol = "SUP";
        assert(SUPER_TOKEN.name().hashString() == tokenName.hashString());
        assert(SUPER_TOKEN.symbol().hashString() == tokenSymbol.hashString());

        // CrossL2Inbox
        uint256 interopStart = CROSS_L2_INBOX.interopStart();
        assert(interopStart > 0 && interopStart <= block.timestamp);

        /* Contracts without any storage intialization on setup */
        // Check that it has a version, not checking which one to make the test more future proof
        string memory emptyString = "";
        bytes32 emptyStringHash = emptyString.hashString();
        assert(ETH_LIQUIDITY.version().hashString() != emptyStringHash);
        assert(L1_BLOCK.version().hashString() != emptyStringHash);
        assert(SUPER_WETH.version().hashString() != emptyStringHash);
        assert(L2_TO_L2_MESSENGER.version().hashString() != emptyStringHash);
        assert(SUPERCHAIN_TOKEN_BRIDGE.version().hashString() != emptyStringHash);
    }

    /// @custom:property-id 1
    /// @custom:property Bridging SuperchainERC20s from the origin to destination decreases the token's totalSupply and
    /// the sender's balance on the origin chain by exactly the input amount.
    function test_sendSuperchainERC20(
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
        isInitialized
        withActor(msg.sender)
    {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the chain id to a valid one
        _chainId = clampGt(_chainId, CHAIN_ID_ONE);
        // Set the amount to a valid one
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Get state before call
        uint256 sTokenTotalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(currentActor());

        // Call the function
        vm.prank(currentActor());
        try SUPERCHAIN_TOKEN_BRIDGE.sendERC20(address(SUPER_TOKEN), _to, _amount, _chainId) {
            assert(SUPER_TOKEN.balanceOf(currentActor()) == actorSTokenBalanceBefore - _amount);
            assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore - _amount);
        } catch {
            // Could revert if the actor doesn't have enough balance
            assert(actorSTokenBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 2
    /// @custom:property Relaying SuperchainERC20s sent from origin increases the token's totalSupply and the
    /// target's balance on the destination chain by exactly the input amount
    function test_relaySuperchainERC20(
        Identifier memory _id,
        address _from,
        uint256 _amount,
        uint256 _nonce,
        uint256 _actorIndex
    )
        public
        isInitialized
        withActor(msg.sender)
    {
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);
        _id.timestamp = clampBetween(_id.timestamp, CROSS_L2_INBOX.interopStart() + 1, block.timestamp);

        // Ensure the message is valid
        address targetActor = getActorByRawIndex(_actorIndex);
        bytes memory message =
            abi.encodeCall(SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_TOKEN), _from, targetActor, _amount));
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, address(SUPERCHAIN_TOKEN_BRIDGE), _nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 sTokenTotalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 actorSTokenBalanceBefore = SUPER_TOKEN.balanceOf(targetActor);

        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: block.chainid,
            _source: _id.chainId,
            _nonce: _nonce,
            _sender: address(SUPERCHAIN_TOKEN_BRIDGE),
            _target: address(SUPERCHAIN_TOKEN_BRIDGE),
            _message: message
        });

        // Relay the message
        vm.prank(relayer);
        /// NOTE: High-level call failing due id's type mismatch, which is wrong since they're the same
        (bool _success,) = address(L2_TO_L2_MESSENGER).call(
            abi.encodeWithSelector(L2_TO_L2_MESSENGER.relayMessage.selector, _id, sentMessage)
        );

        // If it fails, it should only be because the message was already relayed
        if (!_success) assertWithMsg(L2_TO_L2_MESSENGER.successfulMessages(messageHash), "Unknown Revert Error");

        // Check the state is right after the call
        assert(SUPER_TOKEN.balanceOf(targetActor) == actorSTokenBalanceBefore + _amount);
        assert(SUPER_TOKEN.totalSupply() == sTokenTotalSupplyBefore + _amount);
    }

    /// @custom:property-id 3
    /// @custom:property Bridging SuperchainWETH through SuperchainTokenBridge from origin to destination increases the
    /// ETHLiquidity Ether balance, and decreases the sender's SuperchainWETH balance on origin as well as
    /// SuperchainWETH Ether balance by exactly the input amount.
    function test_bridgeSuperchainWETH(
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
        isInitialized
        withActor(msg.sender)
    {
        // Check the target address is valid
        require(_to != address(0) && _to != address(L2_TO_L2_MESSENGER) && _to != address(CROSS_L2_INBOX));
        // Set the chain id to a valid one
        _chainId = clampGt(_chainId, CHAIN_ID_ONE);
        // Set the amount to a valid one
        _amount = clampLte(_amount, type(uint256).max - SUPER_WETH.totalSupply());

        // Get state before call
        uint256 actorSWethBalanceBefore = SUPER_WETH.balanceOf(currentActor());
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        // Call the function
        vm.prank(currentActor());
        try SUPERCHAIN_TOKEN_BRIDGE.sendERC20(address(SUPER_WETH), _to, _amount, _chainId) {
            assert(SUPER_WETH.balanceOf(currentActor()) == actorSWethBalanceBefore - _amount);
            assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore + _amount);
            assert(address(SUPER_WETH).balance == sWethEthBalanceBefore - _amount);
        } catch {
            assert(actorSWethBalanceBefore < _amount);
        }
    }

    /// @custom:property-id 4
    /// @custom:property Relaying SuperchainWETH sent from origin through SuperchainTokenBridge on destination decreases
    /// the ETHLiquidity Ether balance, and increases the target’s SuperchainWETH balance on destination as well as
    /// SuperchainWETH Ether balance by exactly the input amount.
    function test_relaySuperchainWETH(
        Identifier memory _id,
        Message memory _msg,
        uint256 _actorIndex
    )
        public
        isInitialized
        withActor(msg.sender)
    {
        // To avoid overflow pick the higher balance between ETHLiquidity and SUPER_WETH
        _msg.amount = clampLte(
            _msg.amount, type(uint256).max - Helpers.max(address(ETH_LIQUIDITY).balance, address(SUPER_WETH).balance)
        );

        vm.deal(address(ETH_LIQUIDITY), _msg.amount);

        // Ensure the id is valid
        _id.origin = address(L2_TO_L2_MESSENGER);
        _id.timestamp = clampBetween(_id.timestamp, CROSS_L2_INBOX.interopStart() + 1, block.timestamp);

        // Ensure the message is valid
        address targetActor = getActorByRawIndex(_actorIndex);
        address messageTarget = address(SUPERCHAIN_TOKEN_BRIDGE);
        bytes memory message = abi.encodeCall(
            SUPERCHAIN_TOKEN_BRIDGE.relayERC20, (address(SUPER_WETH), _msg.from, targetActor, _msg.amount)
        );
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _msg.nonce), // topics
            abi.encode(address(SUPERCHAIN_TOKEN_BRIDGE), message) // data
        );

        // Get state before call
        uint256 actorSWethBalanceBefore = SUPER_WETH.balanceOf(targetActor);
        uint256 ethLiquidityEthBalanceBefore = address(ETH_LIQUIDITY).balance;
        uint256 sWethEthBalanceBefore = address(SUPER_WETH).balance;

        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: block.chainid,
            _source: _id.chainId,
            _nonce: _msg.nonce,
            _sender: address(SUPERCHAIN_TOKEN_BRIDGE),
            _target: address(SUPERCHAIN_TOKEN_BRIDGE),
            _message: message
        });

        // Relay the message
        vm.prank(relayer);
        /// NOTE: High-level call failing due id's type mismatch, which is wrong since they're the same
        (bool _success,) = address(L2_TO_L2_MESSENGER).call(
            abi.encodeWithSelector(L2_TO_L2_MESSENGER.relayMessage.selector, _id, sentMessage)
        );

        // If it fails, it should only be because the message was already relayed
        if (!_success) assertWithMsg(L2_TO_L2_MESSENGER.successfulMessages(messageHash), "Unknown Revert Error");

        // Check the state is right after the call
        assert(SUPER_WETH.balanceOf(targetActor) == actorSWethBalanceBefore + _msg.amount);
        assert(address(ETH_LIQUIDITY).balance == ethLiquidityEthBalanceBefore - _msg.amount);
        assert(address(SUPER_WETH).balance == sWethEthBalanceBefore + _msg.amount);
    }
}
