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

// TODO change parameter names to start with underscore
contract GasTankTest is Test {
    using stdStorage for StdStorage;

    GasTank public gasTank;
    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    function setUp() public {
        gasTank = new GasTank();
    }

    function testFuzz_deposit_maxDepositExceeded_reverts(uint256 depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        depositAmount = bound(depositAmount, maxDeposit + 1, type(uint256).max);

        vm.deal(address(this), depositAmount);
        vm.expectRevert(IGasTank.MaxDepositExceeded.selector);
        gasTank.deposit{ value: depositAmount }(address(this));
    }

    function testFuzz_deposit_succeeds(uint256 depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        depositAmount = bound(depositAmount, 1, maxDeposit);

        vm.deal(address(this), depositAmount);
        vm.expectEmit(address(gasTank));
        emit IGasTank.Deposit(address(this), depositAmount);
        gasTank.deposit{ value: depositAmount }(address(this));

        assertEq(gasTank.balanceOf(address(this)), depositAmount, "GasTank balance should match the deposited amount");
    }

    function testFuzz_initiateWithdrawal_succeeds(uint256 withdrawalAmount) external {
        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalInitiated(address(this), withdrawalAmount);
        gasTank.initiateWithdrawal(withdrawalAmount);

        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(amount, withdrawalAmount, "GasTank should have recorded the pending withdrawal");
        assertTrue(timestamp == block.timestamp, "GasTank should have recorded the withdrawal timestamp");
    }

    function testFuzz_finalizeWithdrawal_withdrawPending_reverts(uint256 withdrawalAmount) external {
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(0).checked_write(
            block.timestamp
        );
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(1).checked_write(
            withdrawalAmount
        );

        vm.expectRevert(IGasTank.WithdrawPending.selector);
        gasTank.finalizeWithdrawal(address(this));
    }

    // TODO consider balance vs withdrawalAmount logic
    function testFuzz_finalizeWithdrawal_succeeds(uint256 withdrawalAmount, address to, uint256 balance) external {
        vm.deal(address(gasTank), withdrawalAmount);
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(0).checked_write(
            block.timestamp
        );
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(1).checked_write(
            withdrawalAmount
        );
        stdstore.target(address(gasTank)).sig("balanceOf(address)").with_key(address(this)).checked_write(
            withdrawalAmount
        );

        vm.warp(block.timestamp + gasTank.WITHDRAWAL_DELAY());

        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalFinalized(address(this), to, withdrawalAmount);
        gasTank.finalizeWithdrawal(to);

        assertEq(gasTank.balanceOf(address(this)), 0, "GasTank balance should be 0 after finalizing the withdrawal");
        assertEq(to.balance, withdrawalAmount, "Address should have received the withdrawn amount");
    }

    function testFuzz_claim_invalidOrigin_reverts(address origin) external {
        vm.assume(origin != address(gasTank));

        Identifier memory id;
        id.origin = origin;

        vm.expectRevert(IGasTank.InvalidOrigin.selector);
        gasTank.claim(id, address(this), "payload");
    }

    function testFuzz_claim_invalidPayload_reverts(bytes calldata payload) external {
        vm.assume(payload.length >= 32);
        vm.assume(bytes32(payload[:32]) != IGasTank.RelayedMessageGasReceipt.selector);

        Identifier memory id;
        id.origin = address(gasTank);

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

        vm.expectRevert(IGasTank.InvalidPayload.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testFuzz_claim_messageNotAuthorized_reverts(address gasProvider) external {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes memory payload = abi.encode(
            IGasTank.RelayedMessageGasReceipt.selector,
            bytes32(0), // msgHash
            bytes32(0), // originMsgHash
            address(this), // relayer
            0 // relayerCost
        );
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

        vm.expectRevert(IGasTank.MessageNotAuthorized.selector);
        gasTank.claim(id, gasProvider, payload);
    }

    function testFuzz_claim_alreadyClaimed_reverts(bytes32 msgHash, bytes32 originMsgHash) external {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = msgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(
                IGasTank.RelayedMessageGasReceipt.selector, // selector
                originMsgHash, // OriginMsgHash
                address(this), // Relayer
                0 // RelayCost
            ),
            abi.encode(destinationMessageHashes)
        );

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

        stdstore.target(address(gasTank)).sig("claimed(bytes32)").with_key(originMsgHash).checked_write(true);

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

        vm.expectRevert(IGasTank.AlreadyClaimed.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testFuzz_claim_insufficientBalance_reverts(
        uint256 basefee,
        bytes32 msgHash,
        bytes32 originMsgHash
    )
        external
    {
        basefee = bound(basefee, 1, type(uint256).max / 1_000_000);
        vm.fee(basefee);

        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = msgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(
                IGasTank.RelayedMessageGasReceipt.selector, // log selector
                originMsgHash,
                address(this), // Relayer
                1 //relayCost
            ),
            abi.encode(
                destinationMessageHashes // destinationMessageHashes
            )
        );

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

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

        vm.expectRevert(IGasTank.InsufficientBalance.selector);
        gasTank.claim(id, address(this), payload);
    }

    function testFuzz_claim_succeeds(
        uint256 baseFee,
        uint256 relayCost,
        bytes32 msgHash,
        bytes32 originMsgHash
    )
        external
    {
        // vm.assume(msgHash != originMsgHash);
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        uint256 maxBaseFee = (maxDeposit / 100_000) - 1;
        baseFee = bound(baseFee, 1, maxBaseFee);
        vm.fee(baseFee);
        uint256 claimCost = gasTank.claimOverhead(1);
        vm.assume(claimCost < maxDeposit);
        relayCost = bound(relayCost, 1, (maxDeposit - claimCost));

        uint256 totalCost = claimCost + relayCost;
        vm.deal(address(this), totalCost);
        gasTank.deposit{ value: totalCost }(address(this));

        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = msgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(
                IGasTank.RelayedMessageGasReceipt.selector, // log selector
                originMsgHash,
                address(this), // Relayer
                relayCost
            ),
            abi.encode(
                destinationMessageHashes // destinationMessageHashes
            )
        );

        stdstore.target(address(gasTank)).sig("flaggedMessages(address,bytes32)").with_key(address(this)).with_key(
            originMsgHash
        ).checked_write(true);

        // vm.expectCall?
        vm.mockCall(
            address(MESSENGER), abi.encodeWithSignature("sentMessages(bytes32)", originMsgHash), abi.encode(true)
        );

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

    // TODO make test with a nested message
    function testFuzz_relayMessage_succeeds() public {
        // Prepare a dummy identifier and message
        Identifier memory id;
        id.chainId = 10;
        id.origin = address(gasTank);
        uint256 dstChainId = 11;
        uint256 srcChainId = 10;
        uint256 nonce = 1;
        address target = address(1);

        bytes memory dstCallData = abi.encodeWithSignature("doSomething()");
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(
                IL2ToL2CrossDomainMessenger.SentMessage.selector,
                dstChainId, // destination
                target, // target
                nonce // nonce
            ),
            abi.encode(
                address(this), // sender
                dstCallData // dstCallData
            )
        );

        bytes32 originMessageHash = Hashing.hashL2toL2CrossDomainMessage(
            dstChainId, // destChain
            srcChainId, // srcChain
            nonce, // nonce
            address(this), // sender
            target, // target
            dstCallData
        );

        // Call relayMessage
        vm.expectCall(address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("messageNonce()"));
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(uint240(1), uint240(1)); // nonceBefore, version
        mocks[1] = abi.encode(uint240(1), uint240(1)); // nonceAfter, version
        vm.mockCalls(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("messageNonce()"), mocks
        );
        vm.expectCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("relayMessage((address,uint256,uint256,uint256,uint256),bytes)")
        );
        vm.mockCall(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
            abi.encodeWithSignature("relayMessage((address,uint256,uint256,uint256,uint256),bytes)"),
            abi.encode("")
        );
        vm.expectCall(address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("messageNonce()"));

        bytes32[] memory destinationMessageHashes = new bytes32[](0);
        uint256 gasCost = (3945 + (3_000 + 0 * 300)) * 1; // real: 7184
        console.log("Predicted gasCost", gasCost);
        // 3850
        // 34070-31553 = 2517 (event gas usage)

        vm.expectEmit(address(gasTank));
        emit IGasTank.RelayedMessageGasReceipt(originMessageHash, address(this), gasCost, destinationMessageHashes);
        vm.fee(1);
        gasTank.relayMessage(id, sentMessage);
    }
}
