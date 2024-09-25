// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IERC20 } from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/interfaces/IL2ToL2CrossDomainMessenger.sol";

// Target contract
import { SuperchainERC20Bridge } from "src/L2/SuperchainERC20Bridge.sol";
import { ISuperchainERC20Bridge } from "src/L2/interfaces/ISuperchainERC20Bridge.sol";

/// @notice Mock contract for the SuperchainERC20 contract so tests can mint and burn tokens.
contract SuperchainERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) { }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) public {
        _burn(_account, _amount);
    }
}

/// @title SuperchainERC20BridgeTest
/// @notice Contract for testing the SuperchainERC20Bridge contract.
contract SuperchainERC20BridgeTest is Test {
    address internal constant ZERO_ADDRESS = address(0);
    string internal constant NAME = "SuperchainERC20";
    string internal constant SYMBOL = "SCE";
    address internal constant MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    SuperchainERC20Mock public superchainERC20;
    SuperchainERC20Bridge public superchainERC20Bridge;

    /// @notice Sets up the test suite.
    function setUp() public {
        superchainERC20 = new SuperchainERC20Mock(NAME, SYMBOL);
        superchainERC20Bridge = new SuperchainERC20Bridge();
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Tests the `sendERC20` function burns the sender tokens, sends the message, and emits the `SendERC20`
    /// event.
    function testFuzz_sendERC20_succeeds(address _sender, address _to, uint256 _amount, uint256 _chainId) external {
        // Ensure `_sender` is not the zero address
        vm.assume(_sender != ZERO_ADDRESS);
        vm.assume(_to != ZERO_ADDRESS);

        // Mint some tokens to the sender so then they can be sent
        superchainERC20.mint(_sender, _amount);

        // Get the total supply and balance of `_sender` before the send to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _senderBalanceBefore = superchainERC20.balanceOf(_sender);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(address(superchainERC20));
        emit IERC20.Transfer(_sender, ZERO_ADDRESS, _amount);

        // Look for the emit of the `SendERC20` event
        vm.expectEmit(address(superchainERC20Bridge));
        emit ISuperchainERC20Bridge.SendERC20(address(superchainERC20), _sender, _to, _amount, _chainId);

        // Mock the call over the `sendMessage` function and expect it to be called properly
        bytes memory _message =
            abi.encodeCall(superchainERC20Bridge.relayERC20, (address(superchainERC20), _sender, _to, _amount));
        _mockAndExpect(
            MESSENGER,
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessenger.sendMessage.selector, _chainId, address(superchainERC20Bridge), _message
            ),
            abi.encode("")
        );

        // Call the `sendERC20` function
        vm.prank(_sender);
        superchainERC20Bridge.sendERC20(address(superchainERC20), _to, _amount, _chainId);

        // Check the total supply and balance of `_sender` after the send were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(superchainERC20.balanceOf(_sender), _senderBalanceBefore - _amount);
    }

    /// @notice Tests the `relayERC20` function reverts when the caller is not the L2ToL2CrossDomainMessenger.
    function testFuzz_relayERC20_notMessenger_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the messenger
        vm.assume(_caller != MESSENGER);
        vm.assume(_to != ZERO_ADDRESS);

        // Expect the revert with `CallerNotL2ToL2CrossDomainMessenger` selector
        vm.expectRevert(ISuperchainERC20Bridge.CallerNotL2ToL2CrossDomainMessenger.selector);

        // Call the `relayERC20` function with the non-messenger caller
        vm.prank(_caller);
        superchainERC20Bridge.relayERC20(address(superchainERC20), _caller, _to, _amount);
    }

    /// @notice Tests the `relayERC20` function reverts when the `crossDomainMessageSender` that sent the message is not
    /// the same SuperchainERC20Bridge.
    function testFuzz_relayERC20_notCrossDomainSender_reverts(
        address _crossDomainMessageSender,
        address _to,
        uint256 _amount
    )
        public
    {
        vm.assume(_to != ZERO_ADDRESS);
        vm.assume(_crossDomainMessageSender != address(superchainERC20Bridge));

        // Mock the call over the `crossDomainMessageSender` function setting a wrong sender
        vm.mockCall(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
            abi.encode(_crossDomainMessageSender)
        );

        // Expect the revert with `InvalidCrossDomainSender` selector
        vm.expectRevert(ISuperchainERC20Bridge.InvalidCrossDomainSender.selector);

        // Call the `relayERC20` function with the sender caller
        vm.prank(MESSENGER);
        superchainERC20Bridge.relayERC20(address(superchainERC20), _crossDomainMessageSender, _to, _amount);
    }

    /// @notice Tests the `relayERC20` mints the proper amount and emits the `RelayERC20` event.
    function testFuzz_relayERC20_succeeds(address _from, address _to, uint256 _amount, uint256 _source) public {
        vm.assume(_from != ZERO_ADDRESS);
        vm.assume(_to != ZERO_ADDRESS);

        // Mock the call over the `crossDomainMessageSender` function setting the same address as value
        _mockAndExpect(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
            abi.encode(address(superchainERC20Bridge))
        );

        // Mock the call over the `crossDomainMessageSource` function setting the source chain ID as value
        _mockAndExpect(
            MESSENGER,
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
            abi.encode(_source)
        );

        // Get the total supply and balance of `_to` before the relay to compare later on the assertions
        uint256 _totalSupplyBefore = superchainERC20.totalSupply();
        uint256 _toBalanceBefore = superchainERC20.balanceOf(_to);

        // Look for the emit of the `Transfer` event
        vm.expectEmit(address(superchainERC20));
        emit IERC20.Transfer(ZERO_ADDRESS, _to, _amount);

        // Look for the emit of the `RelayERC20` event
        vm.expectEmit(address(superchainERC20Bridge));
        emit ISuperchainERC20Bridge.RelayERC20(address(superchainERC20), _from, _to, _amount, _source);

        // Call the `relayERC20` function with the messenger caller
        vm.prank(MESSENGER);
        superchainERC20Bridge.relayERC20(address(superchainERC20), _from, _to, _amount);

        // Check the total supply and balance of `_to` after the relay were updated correctly
        assertEq(superchainERC20.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(superchainERC20.balanceOf(_to), _toBalanceBefore + _amount);
    }
}
