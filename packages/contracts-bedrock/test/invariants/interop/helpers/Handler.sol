// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    Setup,
    Preinstalls,
    Constants,
    Predeploys,
    IDisputeGameFactory,
    ISystemConfig,
    ISuperchainConfigInterop,
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

import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

contract Handler is Setup {
    struct Message {
        address from;
        uint256 amount;
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

    function handler_transferSuperchainERC20(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_TOKEN.balanceOf(address(actor)));

        (bool success,) = actor.directCall(
            address(SUPER_TOKEN), _ZERO_VALUE, abi.encodeWithSelector(SUPER_TOKEN.transfer.selector, _to, _amount)
        );
        assert(success);
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
        (bool success,) = fromActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.approve.selector, address(callerActor), _amount)
        );
        assert(success);

        // Transfer the tokens
        (success,) = callerActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.transferFrom.selector, address(fromActor), _to, _amount)
        );
        assert(success);
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
        (bool success,) = callerActor.directCall(
            address(SUPER_TOKEN),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_TOKEN.transferFrom.selector, fromEOA, address(callerActor), _amount)
        );
        if (success) {
            assert(SUPER_TOKEN.balanceOf(address(callerActor)) == callerActorBalanceBefore + _amount);
        } else {
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

        (bool success,) = actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.withdraw.selector, _value)
        );
        assert(success);
        _ghost_superWethBalancesSum -= _value;
    }

    function handler_transferSuperchainWETH(address _to, uint256 _amount, uint256 _actorIndex) public initialize {
        Actors actor = randomActor(_actorIndex);
        _amount = clampLte(_amount, SUPER_WETH.balanceOf(address(actor)));

        (bool success,) = actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.transfer.selector, _to, _amount)
        );
        assert(success);
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
        (bool success,) = fromActor.directCall(
            address(SUPER_WETH),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_WETH.approve.selector, address(callerActor), _amount)
        );
        assert(success);

        // Transfer the tokens
        (success,) = callerActor.directCall(
            address(SUPER_WETH),
            _ZERO_VALUE,
            abi.encodeWithSelector(SUPER_WETH.transferFrom.selector, address(fromActor), _to, _amount)
        );
        assert(success);
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
        bool success = actor.callL2ToL2MessengerRelayMessage(_id, sentMessage);
        assert(success);
        // Check the Ether balances
        assert(address(ETH_LIQUIDITY).balance == _ethLiquidityBefore - _message.amount);
        assert(targetActor.balance == _tagretActorBalanceBefore + _message.amount);
        // The total supply of superchain WETH should not change
        assert(SUPER_WETH.totalSupply() == _sWETHTotalSupplyBefore);
    }

    function handler_migrateAndAddL1Dependency() public initialize {
        require(!_ghost_isMigrated);

        // Upgrade the superchain config to the new implementation through the proxy admin
        (bool success,) = proxyOwner.directCall(
            address(proxyAdmin),
            _ZERO_VALUE,
            abi.encodeWithSelector(
                ProxyAdmin.upgrade.selector, address(SUPERCHAIN_CONFIG), address(new StorageSetter())
            )
        );
        assert(success);

        // Reset the initialized flag to enable the new implementation to be initialized
        try StorageSetter(address(SUPERCHAIN_CONFIG)).setBytes32(bytes32(0), bytes32(abi.encodePacked(false))) {
            // Assert the `_initialized` slot was set to false
            assert(StorageSetter(address(SUPERCHAIN_CONFIG)).getBool(bytes32(0)) == false);
        } catch {
            assert(false);
        }

        // Upgrade the superchain config interop to the new implementation through the proxy admin
        (success,) = proxyOwner.directCall(
            address(proxyAdmin),
            _ZERO_VALUE,
            abi.encodeWithSelector(
                ProxyAdmin.upgrade.selector, address(SUPERCHAIN_CONFIG), DEPLOYER_8_15.deploySuperchainConfigInterop()
            )
        );
        assert(success);

        // Initialize the superchain config interop
        try SUPERCHAIN_CONFIG.initialize(guardian, false, clusterManager, sharedLockboxAddress) {
            assert(address(SUPERCHAIN_CONFIG.sharedLockbox()) == sharedLockboxAddress);
            assert(address(SUPERCHAIN_CONFIG.clusterManager()) == clusterManager);
        } catch {
            assert(false);
        }

        // Upgrade the portal to the new implementation through the proxy admin
        (success,) = proxyOwner.directCall(
            address(proxyAdmin),
            _ZERO_VALUE,
            abi.encodeWithSelector(ProxyAdmin.upgrade.selector, address(PORTAL), address(new StorageSetter()))
        );
        assert(success);

        // Reset the initialized flag to enable the new implementation to be initialized
        try StorageSetter(address(PORTAL)).setBytes32(bytes32(0), bytes32(abi.encodePacked(false))) {
            // Assert the `_initialized` slot was set to false
            assert(StorageSetter(address(PORTAL)).getBool(bytes32(0)) == false);
        } catch {
            assert(false);
        }

        // Deploy the new implementation
        address newImplementation =
            DEPLOYER_8_15.deployOptimismPortalInterop(PROOF_MATURITY_DELAY_SECONDS, DISPUTE_GAME_FINALITY_DELAY_SECONDS);
        // Upgrade the portal to the new implementation through the proxy admin
        bytes memory initializeCall = abi.encodeCall(
            OptimismPortalInterop.initialize,
            (
                IDisputeGameFactory(_disputeGameFactory),
                ISystemConfig(systemConfigAddress),
                ISuperchainConfigInterop(superchainConfigAddress),
                GameType.wrap(0)
            )
        );

        // Upgrade the portal to the new implementation through the proxy admin and call the initialize function
        (success,) = proxyOwner.directCall(
            address(proxyAdmin),
            _ZERO_VALUE,
            abi.encodeWithSelector(
                ProxyAdmin.upgradeAndCall.selector, address(PORTAL), newImplementation, initializeCall
            )
        );
        assert(success);
        assert(address(PORTAL.sharedLockbox()) == address(SHARED_LOCKBOX));

        // Get balances before
        uint256 sharedLockboxBalanceBefore = address(SHARED_LOCKBOX).balance;
        uint256 portalBalanceBefore = address(PORTAL).balance;

        // Add chain A to the dependency set, using the cluster manager as the actor to avoid the prank cheatcode
        (success,) = Actors(payable(clusterManager)).directCall(
            superchainConfigAddress,
            0,
            abi.encodeCall(SUPERCHAIN_CONFIG.addDependency, (block.chainid, systemConfigAddress))
        );
        assert(success);

        // Ensure the chain was added to the dependency set and the portal was migrated
        assert(SUPERCHAIN_CONFIG.isInDependencySet(block.chainid));
        assert(SUPERCHAIN_CONFIG.authorizedPortals(address(PORTAL)));
        assert(PORTAL.migrated());
        // Ensure the portal transferred all its balance to the SharedLockbox
        assert(address(PORTAL).balance == 0);
        assert(address(SHARED_LOCKBOX).balance == sharedLockboxBalanceBefore + portalBalanceBefore);

        _ghost_isMigrated = true;
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
    function handler_SendETH(address payable _to, uint256 _amount) public initialize {
        _amount = clampBetween(_amount, 1, 1 ether);
        // Since the Medusa.callSequenceLength is set 50, the max amount of ether that can be sent is 50 * 1 ether.
        vm.deal(address(this), _amount);
        new SafeSend{ value: _amount }(_to);

        if (_to == address(SUPER_WETH)) _ghost_superWethEtherSent += _amount;
    }
}
