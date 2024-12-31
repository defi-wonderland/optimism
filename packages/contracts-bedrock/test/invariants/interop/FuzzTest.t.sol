// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup, Constants, ConfigType, GameType } from "./Setup.sol";
import { Helpers } from "./utils/Helpers.sol";

contract FuzzTest is Setup {
    using Helpers for string;

    /// @notice Tests the contracts vars are set up correctly
    function test_setup() public view {
        /* Contracts with some storage intialization on setup */
        // Portal
        assert(PORTAL.proofMaturityDelaySeconds() == 1 weeks);
        assert(PORTAL.disputeGameFinalityDelaySeconds() == 3.5 days);
        assert(address(PORTAL.systemConfig()) == address(SYSTEM_CONFIG));
        assert(address(PORTAL.superchainConfig()) == address(SUPERCHAIN_CONFIG));
        assert(address(PORTAL.disputeGameFactory()) == _disputeGameFactory);

        // Shared Lockbox
        assert(address(SHARED_LOCKBOX.SUPERCHAIN_CONFIG()) == address(SUPERCHAIN_CONFIG));

        // Superchain Config
        assert(address(SUPERCHAIN_CONFIG.SHARED_LOCKBOX()) == address(SHARED_LOCKBOX));
        assert(SUPERCHAIN_CONFIG.guardian() == guardian);
        assert(SUPERCHAIN_CONFIG.dependencyManager() == dependencyManager);
        assert(SUPERCHAIN_CONFIG.paused() == false);

        // System Config
        // assert(SYSTEM_CONFIG.startBlock(), block.number);
        // TODO: Do initializations

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
}
