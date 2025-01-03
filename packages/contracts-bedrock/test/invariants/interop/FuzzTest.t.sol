// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup, Constants, ConfigType, GameType, Predeploys } from "./Setup.sol";
import { Helpers } from "./utils/Helpers.sol";
import { Actors } from "./Actors.t.sol";

contract FuzzTest is Setup, Actors {
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

        // // System Config
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

        /* Contracts without any storage intialization on setup */
        // Check that it has a version, not checking which one to make the test more future proof
        string memory emptyString = "";
        bytes32 emptyStringHash = emptyString.hashString();
        assert(ETH_LIQUIDITY.version().hashString() != emptyStringHash);
        assert(L1_BLOCK.version().hashString() != emptyStringHash);
        assert(SUPER_WETH.version().hashString() != emptyStringHash);
        assert(CROSS_L2_INBOX.version().hashString() != emptyStringHash);
        assert(L2_TO_L2_MESSENGER.version().hashString() != emptyStringHash);
        assert(SUPERCHAIN_TOKEN_BRIDGE.version().hashString() != emptyStringHash);
    }

    /// Prop-1:
    /// Bridging SuperchainERC20s from the origin to the destination chain decreases the token's
    /// totalSupply and the sender's balance on the origin chain by exactly the input amount.
    function test_SuperchainERC20Sending(
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
        isInitialized
        withActor(msg.sender)
    {
        vm.assume(_to != address(0));
        vm.assume(_to != address(CROSS_L2_INBOX));
        vm.assume(_to != address(L2_TO_L2_MESSENGER));

        _chainId = clampGt(_chainId, CHAIN_ID);

        // Mint tokens to the actor
        SUPER_TOKEN.mint(currentActor(), _amount);

        uint256 totalSupplyBefore = SUPER_TOKEN.totalSupply();
        uint256 balanceBefore = SUPER_TOKEN.balanceOf(currentActor());

        // Call the function
        vm.prank(currentActor());
        try SUPERCHAIN_TOKEN_BRIDGE.sendERC20(address(SUPER_TOKEN), _to, _amount, _chainId) {
            assert(SUPER_TOKEN.balanceOf(currentActor()) == balanceBefore - _amount);
            assert(SUPER_TOKEN.totalSupply() == totalSupplyBefore - _amount);
        } catch {
            assert(false);
        }
    }
}
