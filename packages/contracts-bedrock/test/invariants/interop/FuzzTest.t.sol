// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Constants, ConfigType, GameType, Predeploys } from "./Setup.sol";
import { Handler } from "./Handler.t.sol";
import { Helpers } from "./utils/Helpers.sol";
import { console } from "forge-std/Console.sol";

contract FuzzTest is Handler {
    using Helpers for *;

    bool initialized;

    /// NOTE: Using this modifier because the initialization is not working when called inside the constructor on medusa
    modifier isInitialized() {
        if (!initialized) {
            _initializeEverything();
            initialized = true;
            _;
        }
    }

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
        assert(SYSTEM_CONFIG.startBlock() == block.number);
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
        _chainId = clampGt(_chainId, CHAIN_ID);
        // Set the amount to a valid one
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

        // Mint tokens to the actor
        SUPER_TOKEN.mint(currentActor(), _amount);

        // Get state before call
        uint256 totalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 balanceBefore = SUPER_TOKEN.balanceOf(currentActor());

        // Call the function
        vm.prank(currentActor());
        try SUPERCHAIN_TOKEN_BRIDGE.sendERC20(address(SUPER_TOKEN), _to, _amount, _chainId) {
            assert(SUPER_TOKEN.balanceOf(currentActor()) == balanceBefore - _amount);
            assert(SUPER_TOKEN.totalSupply() == totalSupplyBefore - _amount);
        } catch {
            // TODO: make possible to revert due to insufficient balance
            assert(false);
        }
    }

    /// @custom:property-id 2
    /// @custom:property Relaying SuperchainERC20s sent from origin increases the token's totalSupply and the
    // target's
    /// balance on the destination chain by exactly the input amount
    function test_relaySuperchainERC20(address _from, address _to, uint256 _amount) public {
        // try L2_TO_L2_MESSENGER.relayMessage(_id, _sentMessage);
    }
}
