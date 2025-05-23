// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test, stdStorage, StdStorage } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Hashing } from "src/libraries/Hashing.sol";

// Target contract
import {
    GasTank
} from "src/L2/GasTank.sol";

// Interfaces
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

import { GasTank } from "src/L2/GasTank.sol";

contract GasTankTest is Test {
  using stdStorage for StdStorage;

  GasTank public gasTank;
  IL2ToL2CrossDomainMessenger public constant MESSENGER =
    IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  event RelayedMessageGasReceipt(
        bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address relayer, uint256 cost
  );
  event Claimed(bytes32 msgHash, address relayer, uint256 amount);

  function setUp() public {
    // Set up the test environment
    gasTank = new GasTank();
  }

  function testDeposit_Exceeded(uint256 depositAmount) external {
    uint256 maxDeposit = gasTank.MAX_DEPOSIT();
    depositAmount = bound(depositAmount, maxDeposit, type(uint256).max);

    vm.deal(address(this), depositAmount);
    vm.expectRevert(GasTank.MaxDepositExceeded.selector);
    gasTank.deposit{value: depositAmount}(address(this));
  }

  function testClaim_InvalidOrigin(address origin) external {
    vm.assume(origin != address(MESSENGER));

    Identifier memory id;
    id.origin = origin;

    vm.expectRevert(GasTank.InvalidOrigin.selector);
    gasTank.claim(id, address(this), "payload");
  }

  function testClaim_InvalidPayload(bytes calldata payload) external {
    vm.assume(payload.length >= 32);
    vm.assume(bytes32(payload[:32]) != RelayedMessageGasReceipt.selector);

    Identifier memory id;
    id.origin = address(MESSENGER);

    vm.expectRevert(GasTank.InvalidPayload.selector);
    gasTank.claim(id, address(this), payload);
  }

  function testClaim_InvalidPayer(address gasProvider) external {
    Identifier memory id;
    id.origin = address(MESSENGER);

    bytes memory payload = abi.encode(
      RelayedMessageGasReceipt.selector,
      bytes32(0), // msgHash
      bytes32(0), // rootMsgHash
      address(this), // relayer
      0 // relayerCost
    );

    vm.expectRevert(GasTank.InvalidPayer.selector);
    gasTank.claim(id, gasProvider, payload);
  }

  function testClaim_AlreadyClaimed(bytes32 msgHash, bytes32 rootMsgHash) external {
    Identifier memory id;
    id.origin = address(MESSENGER);

    bytes memory payload = abi.encode(
      RelayedMessageGasReceipt.selector,
      msgHash,
      rootMsgHash,
      address(this),
      0
    );

    stdstore.target(address(gasTank))
      .sig("flaggedMessages(address,bytes32)")
      .with_key(address(this))
      .with_key(rootMsgHash)
      .checked_write(true);

    stdstore.target(address(gasTank))
      .sig("claimed(bytes32)")
      .with_key(msgHash)
      .checked_write(true);

    vm.expectRevert(GasTank.AlreadyClaimed.selector);
    gasTank.claim(id, address(this), payload);
  }

  function testClaim_InsufficientBalance(uint256 basefee, bytes32 msgHash, bytes32 rootMsgHash) external {
    basefee = bound(basefee, 1, type(uint256).max/100_000);
    vm.fee(basefee);

    Identifier memory id;
    id.origin = address(MESSENGER);

    bytes memory payload = abi.encode(
      RelayedMessageGasReceipt.selector,
      msgHash,
      rootMsgHash,
      address(this),
      0
    );

    stdstore.target(address(gasTank))
      .sig("flaggedMessages(address,bytes32)")
      .with_key(address(this))
      .with_key(rootMsgHash)
      .checked_write(true);

    vm.expectRevert(GasTank.InsufficientBalance.selector);
    gasTank.claim(id, address(this), payload);
  }

  function testClaim_InvalidRootMessage(bytes32 msgHash, bytes32 rootMsgHash, bool sentMessageExists) external {
    Identifier memory id;
    id.origin = address(MESSENGER);

    bytes memory payload = abi.encode(
      RelayedMessageGasReceipt.selector,
      msgHash,
      rootMsgHash,
      address(this),
      0
    );

    stdstore.target(address(gasTank))
      .sig("flaggedMessages(address,bytes32)")
      .with_key(address(this))
      .with_key(rootMsgHash)
      .checked_write(true);

    vm.expectCall(
      address(MESSENGER),
      abi.encodeWithSignature("sentMessages(bytes32)", rootMsgHash)
    );
    vm.mockCall(
      address(MESSENGER),
      abi.encodeWithSignature("sentMessages(bytes32)", rootMsgHash),
      abi.encode(sentMessageExists)
    );

    vm.assume(!sentMessageExists);

    vm.expectRevert(GasTank.InvalidRootMessage.selector);
    gasTank.claim(id, address(this), payload);
  }

  function testClaim(uint256 baseFee, uint256 relayCost, bytes32 msgHash, bytes32 rootMsgHash) external {
    uint256 maxDeposit = gasTank.MAX_DEPOSIT();
    uint256 maxBaseFee = (maxDeposit / 100_000) - 1;
    baseFee = bound(baseFee, 1, maxBaseFee);
    uint256 claimCost = 100_000 * baseFee;
    relayCost = bound(relayCost, 1, (maxDeposit - claimCost));

    vm.fee(baseFee);

    uint256 totalCost = claimCost + relayCost;
    vm.deal(address(this), totalCost);
    gasTank.deposit{value: totalCost}(address(this));

    Identifier memory id;
    id.origin = address(MESSENGER);

    bytes memory payload = abi.encode(
      RelayedMessageGasReceipt.selector,
      msgHash,
      rootMsgHash,
      address(this),
      relayCost
    );

    stdstore.target(address(gasTank))
      .sig("flaggedMessages(address,bytes32)")
      .with_key(address(this))
      .with_key(rootMsgHash)
      .checked_write(true);

    vm.mockCall(
      address(MESSENGER),
      abi.encodeWithSignature("sentMessages(bytes32)", rootMsgHash),
      abi.encode(true)
    );

    vm.expectCall(
      address(Predeploys.CROSS_L2_INBOX),
      abi.encodeWithSignature("validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(payload))
    );
    vm.mockCall(
      address(Predeploys.CROSS_L2_INBOX),
      abi.encodeWithSignature("validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(payload)),
      abi.encode(true)
    );

    vm.expectEmit(address(gasTank));
    emit Claimed(
      msgHash,
      address(this),
      totalCost
    );
    gasTank.claim(id, address(this), payload);

    assertEq(
      gasTank.balanceOf(address(this)),
      0,
      "GasTank balance should be 0"
    );
    assertEq(
      gasTank.claimed(msgHash),
      true,
      "GasTank should not have claimed the message"
    );
    assertEq(
      address(this).balance,
      totalCost,
      "GasTank should not have claimed the root message"
    );
  }
}