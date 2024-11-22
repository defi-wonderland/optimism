// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { LiquidityMigrator } from "src/L1/LiquidityMigrator.sol";
import { SharedLockbox } from "src/L1/SharedLockbox.sol";

// TODO: Inherit from CommonTest once we deploy correctly
contract LiquidityMigratorTest is Test {
    event ETHMigrated(uint256 amount);

    address internal immutable SUPERCHAIN_CONFIG = makeAddr("SuperchainConfig");

    LiquidityMigrator public migrator;
    SharedLockbox public sharedLockbox;

    function setUp() public {
        sharedLockbox = new SharedLockbox(SUPERCHAIN_CONFIG);
        migrator = new LiquidityMigrator(address(sharedLockbox));
    }

    /// @notice Tests the migration of the contract's ETH balance to the SharedLockbox works properly.
    function test_migrateETH_succeeds(uint256 _ethAmount) public {
        vm.deal(address(migrator), _ethAmount);

        // Get the balance of the migrator before the migration to compare later on the assertions
        uint256 _migratorEthBalance = address(migrator).balance;
        uint256 _lockboxBalanceBefore = address(sharedLockbox).balance;

        // Look for the emit of the `ETHMigrated` event
        emit ETHMigrated(_migratorEthBalance);

        // Set the migrator as an authorized portal so it can lock the ETH while migrating
        vm.prank(SUPERCHAIN_CONFIG);
        sharedLockbox.authorizePortal(address(migrator));

        // Call the `migrateETH` function with the amount
        migrator.migrateETH();

        // Assert the balances after the migration happened
        assert(address(migrator).balance == 0);
        assert(address(sharedLockbox).balance == _lockboxBalanceBefore + _migratorEthBalance);
    }
}
