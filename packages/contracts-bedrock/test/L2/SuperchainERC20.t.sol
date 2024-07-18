// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/IL2ToL2CrossDomainMessenger.sol";

// Target contract
import {
    SuperchainERC20,
    CallerNotBridge,
    RelayMessageCallerNotL2ToL2CrossDomainMessenger,
    MessageSenderNotThisSuperchainERC20,
    CallerNotBridge
} from "src/L2/SuperchainERC20.sol";
import { ISuperchainERC20 } from "src/L2/ISuperchainERC20.sol";

/// @title SuperchainERC20Test
/// @dev Contract for testing the SuperchainERC20 contract.
contract SuperchainERC20Test is Test {
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant REMOTE_TOKEN = address(0x123);
    string internal constant NAME = "SuperchainERC20";
    string internal constant SYMBOL = "SCE";
    uint8 internal constant DECIMALS = 18;
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;
    address internal constant MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    SuperchainERC20 public superchainERC20;

    /// @dev Sets up the test suite.
    function setUp() public {
        superchainERC20 = new SuperchainERC20(REMOTE_TOKEN, NAME, SYMBOL, DECIMALS);
    }

    /// @dev Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @dev Test that the bridge's constructor sets the correct values.
    function test_constructor_succeeds() public view {
        assertEq(superchainERC20.name(), NAME);
        assertEq(superchainERC20.symbol(), SYMBOL);
        assertEq(superchainERC20.decimals(), DECIMALS);
        assertEq(superchainERC20.REMOTE_TOKEN(), REMOTE_TOKEN);
    }

    /// @dev Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_mint_callerNotBridge_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != BRIDGE);

        // Expect the revert with `CallerNotBridge` selector
        vm.expectRevert(CallerNotBridge.selector);

        // Call the `mint` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.mint(_to, _amount);
    }

    /// @dev Tests the `mint` function reverts when the amount is zero.
    function testFuzz_mint_zeroAddressTo_reverts(uint256 _amount) public {
        // Expect the revert reason "ERC20: mint to the zero address"
        vm.expectRevert("ERC20: mint to the zero address");

        // Call the `mint` function with the zero address
        vm.prank(BRIDGE);
        superchainERC20.mint({ _to: ZERO_ADDRESS, _amount: _amount });
    }

    /// @dev Tests the `mint` succeeds and emits the `Mint` event.
    function testFuzz_mint_succeeds(address _to, uint256 _amount) public {
        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Get the total supply and balance of `_to` before the mint to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _toBalanceBefore = superchainERC20.balanceOf(_to);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(ZERO_ADDRESS, _to, _amount);

        // Look for the emit of the `Mint` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.Mint(_to, _amount);

        // Call the `mint` function with the bridge caller
        vm.prank(BRIDGE);
        superchainERC20.mint(_to, _amount);

        // Check the total supply and balance of `_to` after the mint were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(superchainERC20.balanceOf(_to), _toBalanceBefore + _amount);
    }

    /// @dev Tests the `burn` function reverts when the caller is not the bridge.
    function testFuzz_burn_callerNotBridge_reverts(address _caller, address _from, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != BRIDGE);

        // Expect the revert with `CallerNotBridge` selector
        vm.expectRevert(CallerNotBridge.selector);

        // Call the `burn` function with the non-bridge caller
        vm.prank(_caller);
        superchainERC20.burn(_from, _amount);
    }

    /// @dev Tests the `burn` function reverts when the amount is zero.
    function testFuzz_burn_zeroAddressFrom_reverts(uint256 _amount) public {
        // Expect the revert reason "ERC20: burn from the zero address"
        vm.expectRevert("ERC20: burn from the zero address");

        // Call the `burn` function with the zero address
        vm.prank(BRIDGE);
        superchainERC20.burn({ _from: ZERO_ADDRESS, _amount: _amount });
    }

    /// @dev Tests the `burn` burns the amount and emits the `Burn` event.
    function testFuzz_burn_succeeds(address _from, uint256 _amount) public {
        // Ensure `_from` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Mint some tokens to `_from` so then they can be burned
        vm.prank(BRIDGE);
        superchainERC20.mint(_from, _amount);

        // Get the total supply and balance of `_from` before the burn to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _fromBalanceBefore = superchainERC20.balanceOf(_from);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(_from, ZERO_ADDRESS, _amount);

        // Look for the emit of the `Burn` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.Burn(_from, _amount);

        // Call the `burn` function with the bridge caller
        vm.prank(BRIDGE);
        superchainERC20.burn(_from, _amount);

        // Check the total supply and balance of `_from` after the burn were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(superchainERC20.balanceOf(_from), _fromBalanceBefore - _amount);
    }

    /// @dev Tests the `sendERC20` function burns the sender tokens, sends the message, and emits the `SentERC20` event.
    function testFuzz_sendERC20_succeeds(address _sender, address _to, uint256 _amount, uint256 _chainId) external {
        // Ensure `_sender` is not the zero address
        vm.assume(_sender != ZERO_ADDRESS);

        // Mint some tokens to the sender so then they can be sent
        vm.prank(BRIDGE);
        superchainERC20.mint(_sender, _amount);

        // Get the total supply and balance of `_sender` before the send to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _senderBalanceBefore = superchainERC20.balanceOf(_sender);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(_sender, ZERO_ADDRESS, _amount);

        // Look for the emit of the `SentERC20` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.SentERC20(_sender, _to, _amount, _chainId);

        // Mock the call over the `sendMessage` function and expect it to be called properly
        bytes memory _message = abi.encodeCall(superchainERC20.relayERC20, (_to, _amount));
        _mockAndExpect(
            MESSENGER,
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessenger.sendMessage.selector, _chainId, address(superchainERC20), _message
            ),
            abi.encode("")
        );

        // Call the `sendERC20` function
        vm.prank(_sender);
        superchainERC20.sendERC20(_to, _amount, _chainId);

        // Check the total supply and balance of `_sender` after the send were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(superchainERC20.balanceOf(_sender), _senderBalanceBefore - _amount);
    }

    /// @dev Tests the `relayERC20` function reverts when the caller is not the L2ToL2CrossDomainMessenger.
    function testFuzz_relayERC20_notMessenger_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the messenger
        vm.assume(_caller != MESSENGER);

        // Expect the revert with `RelayMessageCallerNotL2ToL2CrossDomainMessenger` selector
        vm.expectRevert(RelayMessageCallerNotL2ToL2CrossDomainMessenger.selector);

        // Call the `relayERC20` function with the non-messenger caller
        vm.prank(_caller);
        superchainERC20.relayERC20(_to, _amount);
    }

    /// @dev Tests the `relayERC20` function reverts when the `crossDomainMessageSender` that sent the message is not
    /// the same SuperchainERC20 address.
    function testFuzz_relayERC20_notCrossDomainSender_reverts(
        address _crossDomainMessageSender,
        address _to,
        uint256 _amount
    )
        public
    {
        vm.assume(_crossDomainMessageSender != address(superchainERC20));

        // Mock the call over the `crossDomainMessageSender` function setting a wrong sender
        vm.mockCall(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
            abi.encode(_crossDomainMessageSender)
        );

        // Expect the revert with `MessageSenderNotThisSuperchainERC20` selector
        vm.expectRevert(MessageSenderNotThisSuperchainERC20.selector);

        // Call the `relayERC20` function with the sender caller
        vm.prank(MESSENGER);
        superchainERC20.relayERC20(_to, _amount);
    }

    /// @dev Tests the `relayERC20` function reverts when the `_to` address is the zero address.
    function testFuzz_relayERC20_zeroAddressTo_reverts(uint256 _amount) public {
        // Expect the revert reason "ERC20: mint to the zero address"
        vm.expectRevert("ERC20: mint to the zero address");

        // Mock the call over the `crossDomainMessageSender` function setting the same address as value
        vm.mockCall(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
            abi.encode(address(superchainERC20))
        );

        // Call the `relayERC20` function with the zero address
        vm.prank(MESSENGER);
        superchainERC20.relayERC20({ _to: ZERO_ADDRESS, _amount: _amount });
    }

    /// @dev Tests the `relayERC20` mints the proper amount and emits the `RelayedERC20` event.
    function testFuzz_relayERC20_succeeds(address _to, uint256 _amount) public {
        vm.assume(_to != ZERO_ADDRESS);

        // Mock the call over the `crossDomainMessageSender` function setting the same address as value
        _mockAndExpect(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
            abi.encode(address(superchainERC20))
        );

        // Get the total supply and balance of `_to` before the relay to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _toBalanceBefore = superchainERC20.balanceOf(_to);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit IERC20.Transfer(ZERO_ADDRESS, _to, _amount);

        // Look for the emit of the `RelayedERC20` event
        vm.expectEmit(true, true, true, true, address(superchainERC20));
        emit SuperchainERC20.RelayedERC20(_to, _amount);

        // Call the `relayERC20` function with the messenger caller
        vm.prank(MESSENGER);
        superchainERC20.relayERC20(_to, _amount);

        // Check the total supply and balance of `_to` after the relay were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(superchainERC20.balanceOf(_to), _toBalanceBefore + _amount);
    }

    /// @dev Tests the `decimals` function always returns the correct value.
    function testFuzz_decimals_succeeds(uint8 _decimals) public {
        SuperchainERC20 _newSuperchainERC20 = new SuperchainERC20(REMOTE_TOKEN, NAME, SYMBOL, _decimals);
        assertEq(_newSuperchainERC20.decimals(), _decimals);
    }

    /// @dev Tests the `REMOTE_TOKEN` function always returns the correct value.
    function testFuzz_remoteToken_succeeds(address _remoteToken) public {
        SuperchainERC20 _newSuperchainERC20 = new SuperchainERC20(_remoteToken, NAME, SYMBOL, DECIMALS);
        assertEq(_newSuperchainERC20.REMOTE_TOKEN(), _remoteToken);
    }
}
