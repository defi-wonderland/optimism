// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Unauthorized, ZeroAddress } from "src/libraries/errors/CommonErrors.sol";

// Interfaces
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";
import { ISuperchainETHBridge } from "interfaces/L2/ISuperchainETHBridge.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

/// @title SuperchainETHBridge_Test
/// @notice Contract for testing the SuperchainETHBridge contract.
contract SuperchainETHBridge_Test is CommonTest {
    event SendETH(address indexed from, address indexed to, uint256 amount, uint256 destination);

    event RelayETH(address indexed from, address indexed to, uint256 amount, uint256 source);

    address internal constant ZERO_ADDRESS = address(0);

    /// @notice Test setup.
    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();

        vm.warp(superchainETHBridge.ETH_RATE_LIMIT_ACTIVATION());
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Tests the `bucketCapacity` function.
    function test_bucketCapacity() public {
        assertEq(superchainETHBridge.bucketCapacity(), 0);

        skip(1 days);
        assertEq(superchainETHBridge.bucketCapacity(), 100 ether);

        skip(7 days);
        assertEq(superchainETHBridge.bucketCapacity(), 500 ether);

        skip(14 days);
        assertEq(superchainETHBridge.bucketCapacity(), 1000 ether);

        skip(30 days);
        assertEq(superchainETHBridge.bucketCapacity(), 2000 ether);
    }

    /// @notice Tests the `maxTxETHAmount` function.
    function test_maxTxETHAmount() public {
        assertEq(superchainETHBridge.maxTxETHAmount(), 70 * superchainETHBridge.bucketCapacity() / 100);

        skip(1 days);
        assertEq(superchainETHBridge.maxTxETHAmount(), 70 * superchainETHBridge.bucketCapacity() / 100);

        skip(7 days);
        assertEq(superchainETHBridge.maxTxETHAmount(), 70 * superchainETHBridge.bucketCapacity() / 100);

        skip(14 days);
        assertEq(superchainETHBridge.maxTxETHAmount(), 70 * superchainETHBridge.bucketCapacity() / 100);

        skip(30 days);
        assertEq(superchainETHBridge.maxTxETHAmount(), 70 * superchainETHBridge.bucketCapacity() / 100);
    }

    /// @notice Tests the `bucketAvailable` function.
    function test_bucketAvailable() public {
        (uint256 _bucketAvailable,) = superchainETHBridge.bucketAvailable();
        assertEq(_bucketAvailable, 0);

        skip(1 days);
        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();
        assertEq(_bucketAvailable, 100 ether);

        skip(7 days);
        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();
        assertEq(_bucketAvailable, 500 ether);

        skip(14 days);
        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();
        assertEq(_bucketAvailable, 1000 ether);

        skip(30 days);
        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();
        assertEq(_bucketAvailable, 2000 ether);
    }

    function test_bucketAvailableWithUsage(
        uint256 _skip,
        uint256 _amount,
        uint256 _source,
        address _to,
        address _from
    )
        public
    {
        skip(bound(_skip, 0, 30 days));
        (uint256 _bucketAvailable,) = superchainETHBridge.bucketAvailable();

        _amount = bound(_amount, 0, _bucketAvailable);

        // Arrange
        vm.deal(address(superchainETHBridge), _amount);
        vm.deal(Predeploys.ETH_LIQUIDITY, _amount);
        _mockAndExpect(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageContext, ()),
            abi.encode(address(superchainETHBridge), _source)
        );

        // Call the `RelayETH` function with the messenger caller
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainETHBridge.relayETH(_from, _to, _amount);

        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();

        // Assert
        assertEq(_bucketAvailable, superchainETHBridge.bucketCapacity() - _amount);

        skip(superchainETHBridge.REFILL_TIME_WINDOW());

        (_bucketAvailable,) = superchainETHBridge.bucketAvailable();

        // Assert
        assertEq(_bucketAvailable, superchainETHBridge.bucketCapacity());
    }

    /// @notice Tests the `sendETH` function reverts when the address `_to` is zero.
    function testFuzz_sendETH_zeroAddressTo_reverts(address _sender, uint256 _amount, uint256 _chainId) public {
        // Expect the revert with `ZeroAddress` selector
        vm.expectRevert(ZeroAddress.selector);

        vm.deal(_sender, _amount);
        vm.prank(_sender);
        // Call the `sendETH` function with the zero address as `_to`
        superchainETHBridge.sendETH{ value: _amount }(ZERO_ADDRESS, _chainId);
    }

    /// @notice Tests the `sendETH` function reverts when the amount is greater than the bucket available.
    function testFuzz_sendETH_amountGreatermaxTxETHAmount_reverts(address _sender, uint256 _chainId) public {
        uint256 _amount = superchainETHBridge.maxTxETHAmount() + 1;

        // Expect the revert with `AmountTooHigh` selector
        vm.expectRevert(ISuperchainETHBridge.AmountTooHigh.selector);

        vm.deal(_sender, _amount);
        vm.prank(_sender);
        // Call the `sendETH` function with the zero address as `_to`
        superchainETHBridge.sendETH{ value: _amount }(address(1), _chainId);
    }

    /// @notice Tests the `sendETH` function burns the sender ETH, sends the message, and emits the `SendETH`
    /// event.
    function testFuzz_sendETH_succeeds(
        address _sender,
        address _to,
        uint256 _amount,
        uint256 _chainId,
        bytes32 _msgHash,
        uint256 _skip
    )
        external
    {
        skip(bound(_skip, 1 days, 50 days));

        _amount = bound(_amount, superchainETHBridge.BASE_FEE(), superchainETHBridge.maxTxETHAmount());

        // Assume
        vm.assume(_sender != address(ethLiquidity));
        vm.assume(_sender != ZERO_ADDRESS);
        vm.assume(_to != ZERO_ADDRESS);

        // Arrange
        vm.deal(_sender, _amount);

        // Get the total balance of `_sender` before the send to compare later on the assertions
        uint256 _senderBalanceBefore = _sender.balance;

        uint256 _amountToSend = _amount - superchainETHBridge.calculateFee(_amount);

        // Look for the emit of the `SendETH` event
        vm.expectEmit(address(superchainETHBridge));
        emit SendETH(_sender, _to, _amountToSend, _chainId);

        // Expect the call to the `burn` function in the `ETHLiquidity` contract
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.burn, ()), 1);

        // Mock the call over the `sendMessage` function and expect it to be called properly
        bytes memory _message = abi.encodeCall(superchainETHBridge.relayETH, (_sender, _to, _amountToSend));
        _mockAndExpect(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_chainId, address(superchainETHBridge), _message)),
            abi.encode(_msgHash)
        );

        // Call the `sendETH` function
        vm.prank(_sender);
        bytes32 _returnedMsgHash = superchainETHBridge.sendETH{ value: _amount }(_to, _chainId);

        // Check the message hash was generated correctly
        assertEq(_msgHash, _returnedMsgHash);

        // Check the total supply and balance of `_sender` after the send were updated correctly
        assertEq(_sender.balance, _senderBalanceBefore - _amount);
    }

    /// @notice Tests the `relayETH` function reverts when the caller is not the L2ToL2CrossDomainMessenger.
    function testFuzz_relayETH_notMessenger_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the messenger
        vm.assume(_caller != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Expect the revert with `Unauthorized` selector
        vm.expectRevert(Unauthorized.selector);

        // Call the `relayETH` function with the non-messenger caller
        vm.prank(_caller);
        superchainETHBridge.relayETH(_caller, _to, _amount);
    }

    /// @notice Tests the `relayETH` function reverts when the `crossDomainMessageSender` that sent the message is not
    /// the same SuperchainETHBridge.
    function testFuzz_relayETH_notCrossDomainSender_reverts(
        address _crossDomainMessageSender,
        uint256 _source,
        address _to,
        uint256 _amount,
        uint256 _skip
    )
        public
    {
        skip(bound(_skip, 1 days, 50 days));

        _amount = bound(_amount, superchainETHBridge.BASE_FEE(), superchainETHBridge.maxTxETHAmount());

        vm.assume(_crossDomainMessageSender != address(superchainETHBridge));

        // Mock the call over the `crossDomainMessageContext` function setting a wrong sender
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageContext, ()),
            abi.encode(_crossDomainMessageSender, _source)
        );

        // Expect the revert with `InvalidCrossDomainSender` selector
        vm.expectRevert(ISuperchainETHBridge.InvalidCrossDomainSender.selector);

        // Call the `relayETH` function with the sender caller
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainETHBridge.relayETH(_crossDomainMessageSender, _to, _amount);
    }

    /// @notice Tests the `relayETH` function reverts when the amount is greater than the bucket available.
    function testFuzz_relayETH_amountGreaterThanBucketAvailable_reverts(address _from, address _to) public {
        (uint256 _bucketAvailableAmount,) = superchainETHBridge.bucketAvailable();
        uint256 _amount = _bucketAvailableAmount + 1;
        // Expect the revert with `NoBucketAvailability` selector
        vm.expectRevert(ISuperchainETHBridge.NoBucketAvailability.selector);
        // Call the `relayETH` function with the sender caller
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainETHBridge.relayETH(_from, _to, _amount);
    }

    /// @notice Tests the `relayETH` function relays the proper amount of ETH and emits the `RelayETH` event.
    function testFuzz_relayETH_succeeds(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _source,
        uint256 _skip
    )
        public
    {
        // Assume
        vm.assume(_to != ZERO_ADDRESS);
        assumePayable(_to);

        skip(bound(_skip, 1 days, 50 days));
        _amount = bound(_amount, superchainETHBridge.BASE_FEE(), superchainETHBridge.maxTxETHAmount());

        // Arrange
        vm.deal(address(superchainETHBridge), _amount);
        vm.deal(Predeploys.ETH_LIQUIDITY, _amount);
        _mockAndExpect(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageContext, ()),
            abi.encode(address(superchainETHBridge), _source)
        );

        uint256 _toBalanceBefore = _to.balance;

        // Look for the emit of the `RelayETH` event
        vm.expectEmit(address(superchainETHBridge));
        emit RelayETH(_from, _to, _amount, _source);

        // Expect the call to the `mint` function in the `ETHLiquidity` contract
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.mint, (_amount)), 1);

        // Call the `RelayETH` function with the messenger caller
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainETHBridge.relayETH(_from, _to, _amount);

        assertEq(_to.balance, _toBalanceBefore + _amount);
    }
}
