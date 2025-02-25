// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { Unauthorized, Paused as PausedError } from "src/libraries/errors/CommonErrors.sol";

// Interfaces
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";

import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";

import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

// Test
import { CommonTest } from "test/setup/CommonTest.sol";

import { Predeploys } from "src/libraries/Predeploys.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

contract ETHLockboxTest is CommonTest {
    event ETHLocked(address indexed portal, uint256 amount);

    event ETHUnlocked(address indexed portal, uint256 amount);

    event PortalAuthorized(address indexed portal);

    ProxyAdmin public proxyAdmin = ProxyAdmin(Predeploys.PROXY_ADMIN);

    function setUp() public virtual override {
        super.setUp();
        // TODO: Athorize portal on the lockbox -- check if it needs to go directly on the scripts
    }

    // TODO: Proxy admin owner tests

    /// @notice Tests it reverts when the caller is not an authorized portal.
    function testFuzz_lockETH_unauthorizedPortal_reverts(address _caller) public {
        vm.assume(!ethLockbox.authorizedPortals(_caller));

        // Expect the revert with `Unauthorized` selector
        vm.expectRevert(Unauthorized.selector);

        // Call the `lockETH` function with an unauthorized caller
        vm.prank(_caller);
        ethLockbox.lockETH();
    }

    /// @notice Tests the ETH is correctly locked when the caller is an authorized portal.
    function testFuzz_lockETH_succeeds(uint256 _amount) public {
        // Deal the ETH amount to the portal
        vm.deal(address(optimismPortal2), _amount);

        // Get the balance of the portal and lockbox before the lock to compare later on the assertions
        uint256 _portalBalanceBefore = address(optimismPortal2).balance;
        uint256 _lockboxBalanceBefore = address(ethLockbox).balance;

        // Look for the emit of the `ETHLocked` event
        vm.expectEmit(address(ethLockbox));
        emit ETHLocked(address(optimismPortal2), _amount);

        // Call the `lockETH` function with the portal
        vm.prank(address(optimismPortal2));
        ethLockbox.lockETH{ value: _amount }();

        // Assert the portal's balance decreased and the lockbox's balance increased by the amount locked
        assertEq(address(optimismPortal2).balance, _portalBalanceBefore - _amount);
        assertEq(address(ethLockbox).balance, _lockboxBalanceBefore + _amount);
    }

    /// @notice Tests the ETH is correctly locked when the caller is an authorized portal with different portals.
    function testFuzz_lockETH_multiplePortals_succeeds(address _portal, uint256 _amount) public {
        vm.assume(_portal != address(ethLockbox));

        // Set the portal as an authorized portal
        vm.prank(proxyAdmin.owner());
        ethLockbox.authorizePortal(_portal);

        // Deal the ETH amount to the portal
        vm.deal(_portal, _amount);

        // Get the balance of the portal and lockbox before the lock to compare later on the assertions
        uint256 _portalBalanceBefore = address(_portal).balance;
        uint256 _lockboxBalanceBefore = address(ethLockbox).balance;

        // Look for the emit of the `ETHLocked` event
        vm.expectEmit(address(ethLockbox));
        emit ETHLocked(_portal, _amount);

        // Call the `lockETH` function with the portal
        vm.prank(_portal);
        ethLockbox.lockETH{ value: _amount }();

        // Assert the portal's balance decreased and the lockbox's balance increased by the amount locked
        assertEq(address(_portal).balance, _portalBalanceBefore - _amount);
        assertEq(address(ethLockbox).balance, _lockboxBalanceBefore + _amount);
    }

    /// @notice Tests `unlockETH` reverts when the contract is paused.
    function testFuzz_unlockETH_paused_reverts(address _caller, uint256 _value) public {
        // Mock the superchain config to return true for the paused status
        vm.mockCall(address(superchainConfig), abi.encodeCall(ISuperchainConfig.paused, ()), abi.encode(true));

        // Expect the revert with `Paused` selector
        vm.expectRevert(PausedError.selector);

        // Call the `unlockETH` function with the caller
        vm.prank(_caller);
        ethLockbox.unlockETH(_value);
    }

    /// @notice Tests it reverts when the caller is not an authorized portal.
    function testFuzz_unlockETH_unauthorizedPortal_reverts(address _caller, uint256 _value) public {
        vm.assume(!ethLockbox.authorizedPortals(_caller));

        // Expect the revert with `Unauthorized` selector
        vm.expectRevert(Unauthorized.selector);

        // Call the `unlockETH` function with an unauthorized caller
        vm.prank(_caller);
        ethLockbox.unlockETH(_value);
    }

    /// @notice Tests the ETH is correctly unlocked when the caller is an authorized portal.
    function testFuzz_unlockETH_succeeds(uint256 _value) public {
        // Deal the ETH amount to the lockbox
        vm.deal(address(ethLockbox), _value);

        // Get the balance of the portal and lockbox before the unlock to compare later on the assertions
        uint256 portalBalanceBefore = address(optimismPortal2).balance;
        uint256 lockboxBalanceBefore = address(ethLockbox).balance;

        // Expect `donateETH` function to be called on Portal
        vm.expectCall(address(optimismPortal2), abi.encodeCall(IOptimismPortal.donateETH, ()));

        // Look for the emit of the `ETHUnlocked` event
        vm.expectEmit(address(ethLockbox));
        emit ETHUnlocked(address(optimismPortal2), _value);

        // Call the `unlockETH` function with the portal
        vm.prank(address(optimismPortal2));
        ethLockbox.unlockETH(_value);

        // Assert the portal's balance increased and the lockbox's balance decreased by the amount unlocked
        assertEq(address(optimismPortal2).balance, portalBalanceBefore + _value);
        assertEq(address(ethLockbox).balance, lockboxBalanceBefore - _value);
    }

    /// @notice Tests the ETH is correctly unlocked when the caller is an authorized portal.
    function testFuzz_unlockETH_multiplePortals_succeeds(address _portal, uint256 _value) public {
        vm.assume(_portal != address(ethLockbox));

        // Set the portal as an authorized portal
        vm.prank(proxyAdmin.owner());
        ethLockbox.authorizePortal(_portal);

        // Deal the ETH amount to the lockbox
        vm.deal(address(ethLockbox), _value);

        // Get the balance of the portal and lockbox before the unlock to compare later on the assertions
        uint256 portalBalanceBefore = address(optimismPortal2).balance;
        uint256 lockboxBalanceBefore = address(ethLockbox).balance;

        // Expect `donateETH` function to be called on Portal
        vm.expectCall(address(optimismPortal2), abi.encodeCall(IOptimismPortal.donateETH, ()));

        // Look for the emit of the `ETHUnlocked` event
        vm.expectEmit(address(ethLockbox));
        emit ETHUnlocked(address(optimismPortal2), _value);

        // Call the `unlockETH` function with the portal
        vm.prank(address(optimismPortal2));
        ethLockbox.unlockETH(_value);

        // Assert the portal's balance increased and the lockbox's balance decreased by the amount unlocked
        assertEq(address(optimismPortal2).balance, portalBalanceBefore + _value);
        assertEq(address(ethLockbox).balance, lockboxBalanceBefore - _value);
    }

    /// @notice Tests the paused status is correctly returned.
    function test_paused_succeeds() public {
        // Assert the paused status is false
        assertEq(ethLockbox.paused(), false);

        // Mock the superchain config to return true for the paused status
        vm.mockCall(address(superchainConfig), abi.encodeCall(ISuperchainConfig.paused, ()), abi.encode(true));

        // Assert the paused status is true
        assertEq(ethLockbox.paused(), true);
    }
}
