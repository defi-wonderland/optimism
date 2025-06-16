// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test, stdStorage, StdStorage } from "forge-std/Test.sol";
import { console } from "forge-std/Console.sol";
import { Vm } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Hashing } from "src/libraries/Hashing.sol";

// Target contract
import { GasTank } from "src/L2/GasTank.sol";

// Interfaces
import { IGasTank } from "interfaces/L2/IGasTank.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

import { GasTank } from "src/L2/GasTank.sol";

contract GasTankTest is Test {
    using stdStorage for StdStorage;

    GasTank public gasTank;
    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    function setUp() public {
        gasTank = new GasTank();
    }

    function testDeposit_Exceeded(uint256 depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        depositAmount = bound(depositAmount, maxDeposit + 1, type(uint256).max);

        vm.deal(address(this), depositAmount);
        vm.expectRevert(IGasTank.MaxDepositExceeded.selector);
        gasTank.deposit{ value: depositAmount }(address(this));
    }

    function testDeposit(uint256 depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        depositAmount = bound(depositAmount, 1, maxDeposit);

        vm.deal(address(this), depositAmount);
        vm.expectEmit(address(gasTank));
        emit IGasTank.Deposit(address(this), depositAmount);
        gasTank.deposit{ value: depositAmount }(address(this));

        assertEq(gasTank.balanceOf(address(this)), depositAmount, "GasTank balance should match the deposited amount");
    }

    function testIntiateWithdrawal_InsufficientBalance(uint256 withdrawalAmount) external {
        vm.assume(withdrawalAmount > 0);

        vm.expectRevert(IGasTank.InsufficientBalance.selector);
        gasTank.initiateWithdrawal(withdrawalAmount);
    }

    function testIntiateWithdrawal(uint256 withdrawalAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        withdrawalAmount = bound(withdrawalAmount, 1, maxDeposit);

        vm.deal(address(this), withdrawalAmount);
        gasTank.deposit{ value: withdrawalAmount }(address(this));

        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalInitiated(address(this), withdrawalAmount);
        gasTank.initiateWithdrawal(withdrawalAmount);

        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(amount, withdrawalAmount, "GasTank should have recorded the pending withdrawal");
        assertTrue(timestamp == block.timestamp, "GasTank should have recorded the withdrawal timestamp");
    }

    function testFinalizeWithdrawal_PendingWithdrawal(uint256 withdrawalAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        withdrawalAmount = bound(withdrawalAmount, 1, maxDeposit);
        vm.deal(address(this), withdrawalAmount);
        gasTank.deposit{ value: withdrawalAmount }(address(this));

        gasTank.initiateWithdrawal(withdrawalAmount);

        vm.expectRevert(IGasTank.WithdrawPending.selector);
        gasTank.finalizeWithdrawal(address(this));
    }

    function testFinalizeWithdrawal(uint256 withdrawalAmount, address to) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        withdrawalAmount = bound(withdrawalAmount, 1, maxDeposit);

        vm.deal(address(this), withdrawalAmount);
        gasTank.deposit{ value: withdrawalAmount }(address(this));

        gasTank.initiateWithdrawal(withdrawalAmount);

        vm.warp(block.timestamp + gasTank.WITHDRAWAL_DELAY());

        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalFinalized(address(this), to, withdrawalAmount);
        gasTank.finalizeWithdrawal(to);

        assertEq(gasTank.balanceOf(address(this)), 0, "GasTank balance should be 0 after finalizing the withdrawal");
        assertEq(to.balance, withdrawalAmount, "Address should have received the withdrawn amount");
    }

    function testClaim_InvalidOrigin(address origin) external {
        vm.assume(origin != address(gasTank));

        Identifier memory id;
        id.origin = origin;

        vm.expectRevert(IGasTank.InvalidOrigin.selector);
        gasTank.claim(id, address(this), "payload");
    }

    function testClaim_InvalidPayload(bytes calldata payload) external {
        vm.assume(payload.length >= 32);
        vm.assume(bytes32(payload[:32]) != IGasTank.RelayedMessageGasReceipt.selector);

        Identifier memory id;
        id.origin = address(gasTank);

        vm.expectRevert(IGasTank.InvalidPayload.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testClaim_InvalidPayer(address gasProvider) external {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes memory payload = abi.encode(
            IGasTank.RelayedMessageGasReceipt.selector,
            bytes32(0), // msgHash
            bytes32(0), // originMsgHash
            address(this), // relayer
            0 // relayerCost
        );

        vm.expectRevert(IGasTank.InvalidPayer.selector);
        gasTank.claim(id, gasProvider, payload);
    }

    function testClaim_AlreadyClaimed(bytes32 msgHash, bytes32 originMsgHash) external {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes memory payload =
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, msgHash, originMsgHash, address(this), 0);

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

        stdstore.target(address(gasTank)).sig("claimed(bytes32)").with_key(msgHash).checked_write(true);

        vm.expectRevert(IGasTank.AlreadyClaimed.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testClaim_InsufficientBalance(uint256 basefee, bytes32 msgHash, bytes32 originMsgHash) external {
        basefee = bound(basefee, 1, type(uint256).max / 100_000);
        vm.fee(basefee);

        Identifier memory id;
        id.origin = address(gasTank);

        bytes memory payload =
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, msgHash, originMsgHash, address(this), 0);

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

        vm.expectRevert(IGasTank.InsufficientBalance.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testClaim_Success(uint256 baseFee, uint256 relayCost, bytes32 msgHash, bytes32 originMsgHash) external {
        // vm.assume(msgHash != originMsgHash);
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        uint256 maxBaseFee = (maxDeposit / 100_000) - 1;
        baseFee = bound(baseFee, 1, maxBaseFee);
        uint256 claimCost = 100_000 * baseFee;
        relayCost = bound(relayCost, 1, (maxDeposit - claimCost));

        vm.fee(baseFee);

        uint256 totalCost = claimCost + relayCost;
        vm.deal(address(this), totalCost);
        gasTank.deposit{ value: totalCost }(address(this));

        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = msgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(
                IGasTank.RelayedMessageGasReceipt.selector,  // log selector
                originMsgHash,
                address(this),  // Relayer
                relayCost
            ),
            abi.encode(
                destinationMessageHashes  // destinationMessageHashes
            )
        );

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

        // vm.expectCall?
        vm.mockCall(address(MESSENGER), abi.encodeWithSignature("sentMessages(bytes32)", originMsgHash), abi.encode(true));

        vm.expectCall(
            address(Predeploys.CROSS_L2_INBOX),
            abi.encodeWithSignature(
                "validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(payload)
            )
        );
        vm.mockCall(
            address(Predeploys.CROSS_L2_INBOX),
            abi.encodeWithSignature(
                "validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(payload)
            ),
            abi.encode(true)
        );

        vm.expectEmit(address(gasTank));
        emit IGasTank.Claimed(originMsgHash, address(this), address(this), totalCost);
        gasTank.claim(id, address(this), payload);

        assertEq(gasTank.balanceOf(address(this)), 0, "GasTank balance should be 0");
        assertTrue(gasTank.claimed(originMsgHash), "GasTank should have claimed the root message");
        assertEq(address(this).balance, totalCost, "GasTank should have compensated relayer");
    }

    function testRelayMessage_Success() public {
        // Prepare a dummy identifier and message
        Identifier memory id;
        id.chainId = 10;
        id.origin = address(gasTank);

        bytes memory dstCallData = abi.encodeWithSignature("doSomething()");
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(
                IL2ToL2CrossDomainMessenger.SentMessage.selector,
                uint256(11), // destination
                address(1), // target
                uint256(10) // nonce
            ),
            abi.encode(
                address(this), // sender
                dstCallData  // dstCallData
            )
        );
        // bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage(destination, _source, nonce, sender, target, message);

        // TODO: might need a mock for messageNonce()
        // Call relayMessage
        // vm.expectCall(
        //     address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
        //     abi.encodeWithSignature("messageNonce()")
        // );
        // vm.mockCall(
        //     address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
        //     abi.encodeWithSignature("messageNonce()"),
        //     abi.encode(uint240(0), uint240(0))
        // );
        vm.expectCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("relayMessage((address,uint256,uint256,uint256,uint256),bytes)")
        );
        vm.mockCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("relayMessage((address,uint256,uint256,uint256,uint256),bytes)"),
            abi.encode("")
        );
        // vm.expectCall(
        //     address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
        //     abi.encodeWithSignature("messageNonce()")
        // );
        // vm.mockCall(
        //     address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
        //     abi.encodeWithSignature("messageNonce()"),
        //     abi.encode(uint240(20), uint240(21))
        // );
        vm.expectCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("sentMessages(uint256)")
        );
        vm.mockCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("sentMessages(uint256)"),
            abi.encode(bytes32(0))
        );

        vm.expectEmit(address(gasTank));
        emit IGasTank.RelayedMessageGasReceipt(bytes32(0), address(this), 0, new bytes32[](0));
        gasTank.relayMessage(id, sentMessage);
    }
}