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

contract GasTankTest is Test {
    using stdStorage for StdStorage;

    GasTank public gasTank;
    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    function setUp() public {
        gasTank = new GasTank();
    }

    function testFuzz_deposit_maxDepositExceeded_reverts(uint256 _depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        _depositAmount = bound(_depositAmount, maxDeposit + 1, type(uint256).max);

        vm.deal(address(this), _depositAmount);
        vm.expectRevert(IGasTank.MaxDepositExceeded.selector);
        gasTank.deposit{ value: _depositAmount }(address(this));
    }

    function testFuzz_deposit_succeeds(uint256 _depositAmount) external {
        uint256 maxDeposit = gasTank.MAX_DEPOSIT();
        _depositAmount = bound(_depositAmount, 1, maxDeposit);

        vm.deal(address(this), _depositAmount);
        vm.expectEmit(address(gasTank));
        emit IGasTank.Deposit(address(this), _depositAmount);
        gasTank.deposit{ value: _depositAmount }(address(this));

        assertEq(gasTank.balanceOf(address(this)), _depositAmount, "GasTank balance should match the deposited amount");
    }

    function testFuzz_initiateWithdrawal_succeeds(uint256 _withdrawalAmount) external {
        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalInitiated(address(this), _withdrawalAmount);
        gasTank.initiateWithdrawal(_withdrawalAmount);

        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(amount, _withdrawalAmount, "GasTank should have recorded the pending withdrawal");
        assertTrue(timestamp == block.timestamp, "GasTank should have recorded the withdrawal timestamp");
    }

    function testFuzz_finalizeWithdrawal_withdrawPending_reverts(uint256 _withdrawalAmount) external {
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(0).checked_write(
            block.timestamp
        );
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(1).checked_write(
            _withdrawalAmount
        );

        vm.expectRevert(IGasTank.WithdrawPending.selector);
        gasTank.finalizeWithdrawal(address(this));
    }

    function testFuzz_finalizeWithdrawal_succeeds(uint256 _withdrawalAmount, address _to, uint256 _balance) external {
        uint256 withdrawableAmount = _balance < _withdrawalAmount ? _balance : _withdrawalAmount;
        vm.deal(address(gasTank), withdrawableAmount);

        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(0).checked_write(
            block.timestamp
        );
        stdstore.target(address(gasTank)).sig("withdrawals(address)").with_key(address(this)).depth(1).checked_write(
            _withdrawalAmount
        );
        stdstore.target(address(gasTank)).sig("balanceOf(address)").with_key(address(this)).checked_write(_balance);
        vm.warp(block.timestamp + gasTank.WITHDRAWAL_DELAY());

        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalFinalized(address(this), _to, withdrawableAmount);
        gasTank.finalizeWithdrawal(_to);

        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(timestamp, 0, "GasTank should have deleted the withdrawal timestamp");
        assertEq(amount, 0, "GasTank should have deleted the withdrawal amount");
        assertEq(
            gasTank.balanceOf(address(this)),
            _balance - withdrawableAmount,
            "GasTank balance should be 0 after finalizing the withdrawal"
        );
        assertEq(_to.balance, withdrawableAmount, "Address should have received the withdrawn amount");
    }

    function testFuzz_authorizeClaim_succeeds(bytes32 _messageHash) external {
        vm.expectEmit(address(gasTank));
        emit IGasTank.AuthorizedClaim(address(this), _messageHash);
        gasTank.authorizeClaim(_messageHash);

        assertTrue(gasTank.authorizedMessages(address(this), _messageHash), "GasTank should have flagged the message");
    }

    function testFuzz_relayMessage_succeeds(uint256 _baseFee, uint256 _numHashes) external {
        // Assumptions
        _baseFee = bound(_baseFee, 1, type(uint256).max / 1_000_000);
        _numHashes = bound(_numHashes, 0, 0); // TODO increase upper bound
        vm.fee(_baseFee);

        // Prepare call data // TODO fuzz these too and calculate gas cost
        Identifier memory id;
        bytes memory sentMessage;
        bytes32 originMessageHash;
        address sender = address(this);
        {
            uint256 srcChainId = 10;
            id.chainId = srcChainId;
            id.origin = address(gasTank);
            uint256 dstChainId = 11;
            uint256 nonce = 1;
            address target = address(1);

            bytes memory dstCallData = abi.encodeWithSignature("doSomething()");
            sentMessage = abi.encodePacked(
                abi.encode(IL2ToL2CrossDomainMessenger.SentMessage.selector, dstChainId, target, nonce),
                abi.encode(sender, dstCallData)
            );

            originMessageHash =
                Hashing.hashL2toL2CrossDomainMessage(dstChainId, srcChainId, nonce, sender, target, dstCallData);
        }
        // Call relayMessage
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(uint240(1), uint240(1)); // nonceBefore, version
        mocks[1] = abi.encode(uint240(1), uint240(1)); // nonceAfter, version
        vm.mockCalls(
            address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("messageNonce()"), mocks
        );
        vm.expectCall(address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("messageNonce()"));

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

        bytes32[] memory destinationMessageHashes = new bytes32[](_numHashes);
        for (uint256 i; i < _numHashes; i++) {
            vm.expectCall(
                address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER), abi.encodeWithSignature("sentMessages(bytes32)")
            );
            vm.mockCall(
                address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
                abi.encodeWithSignature("sentMessages(bytes32)"),
                abi.encode("")
            );
            destinationMessageHashes[i] = bytes32(0);
        }

        uint256 memoryExpansionGas = (420 * _numHashes) + (_numHashes * _numHashes) / 512;
        uint256 totalGasCost = _baseFee
            * (
                4_423 // execution fee (assuming 0 nested messages)
                    + (35_000 + memoryExpansionGas)
            ); // TODO use dynamic calculation based on numHashes

        vm.expectEmit(address(gasTank));
        emit IGasTank.RelayedMessageGasReceipt(originMessageHash, address(this), totalGasCost, destinationMessageHashes);
        gasTank.relayMessage(id, sentMessage);
    }

    function testFuzz_claim_invalidOrigin_reverts(address _origin) external {
        vm.assume(_origin != address(gasTank));

        Identifier memory id;
        id.origin = _origin;

        vm.expectRevert(IGasTank.InvalidOrigin.selector);
        gasTank.claim(id, address(this), "payload");
    }

    function testFuzz_claim_invalidPayload_reverts(bytes calldata _payload) external {
        vm.assume(_payload.length >= 32);
        vm.assume(bytes32(_payload[:32]) != IGasTank.RelayedMessageGasReceipt.selector);

        Identifier memory id;
        id.origin = address(gasTank);

        vm.expectCall(
            address(Predeploys.CROSS_L2_INBOX),
            abi.encodeWithSignature(
                "validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(_payload)
            )
        );
        vm.mockCall(
            address(Predeploys.CROSS_L2_INBOX),
            abi.encodeWithSignature(
                "validateMessage((address,uint256,uint256,uint256,uint256),bytes32)", id, keccak256(_payload)
            ),
            abi.encode(true)
        );

        vm.expectRevert(IGasTank.InvalidPayload.selector);
        gasTank.claim(id, address(this), _payload);
    }

    function testFuzz_claim_messageNotAuthorized_reverts(
        bytes32 _originMsgHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider
    )
        external
    {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = _destinationMsgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _originMsgHash, _relayer),
            abi.encode(
                _relayCost,
                destinationMessageHashes // destinationMessageHashes
            )
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
        gasTank.claim(id, _gasProvider, payload);
    }

    function testFuzz_claim_alreadyClaimed_reverts(
        bytes32 _originMsgHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider
    )
        external
    {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = _destinationMsgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _originMsgHash, _relayer),
            abi.encode(
                _relayCost,
                destinationMessageHashes // destinationMessageHashes
            )
        );

        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _originMsgHash
        ).checked_write(true);

        stdstore.target(address(gasTank)).sig("claimed(bytes32)").with_key(_originMsgHash).checked_write(true);

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
        gasTank.claim(id, _gasProvider, payload);
    }

    function testFuzz_claim_insufficientBalance_reverts(
        uint256 _baseFee,
        bytes32 _originMsgHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider
    )
        external
    {
        _relayCost = bound(_relayCost, 1, type(uint256).max);
        _baseFee = bound(_baseFee, 1, type(uint256).max / 1_000_000);
        vm.fee(_baseFee);

        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = _destinationMsgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _originMsgHash, _relayer),
            abi.encode(
                _relayCost,
                destinationMessageHashes // destinationMessageHashes
            )
        );

        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _originMsgHash
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
        gasTank.claim(id, _gasProvider, payload);
    }

    // TODO add scenario with multiple destination messages
    function testFuzz_claim_succeeds(
        uint256 _baseFee,
        bytes32 _originMsgHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider,
        uint256 _relayerExtraBalance
    )
        external
    {
        // Assumptions
        vm.assume(_relayer != address(this));

        {
            uint256 maxDeposit = gasTank.MAX_DEPOSIT();
            _relayerExtraBalance = bound(_relayerExtraBalance, 0, maxDeposit - 1);
            uint256 maxBaseFee = (maxDeposit / 1_000_000) - 1;
            _baseFee = bound(_baseFee, 1, maxBaseFee);
            vm.fee(_baseFee);
            _relayCost = bound(_relayCost, 1, maxDeposit - _relayerExtraBalance);
        }

        // Setting storage
        stdstore.target(address(gasTank)).sig("balanceOf(address)").with_key(_gasProvider).checked_write(
            _relayCost + _relayerExtraBalance
        );
        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _originMsgHash
        ).checked_write(true);

        // Prepare call data
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory destinationMessageHashes = new bytes32[](1);
        destinationMessageHashes[0] = _destinationMsgHash;

        bytes memory payload = abi.encodePacked(
            abi.encode(
                IGasTank.RelayedMessageGasReceipt.selector, // log selector
                _originMsgHash,
                _relayer
            ),
            abi.encode(_relayCost, destinationMessageHashes)
        );

        // Expect calls
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

        // Call claim
        uint256 claimCost = gasTank.claimOverhead(1, _baseFee);
        claimCost = _relayerExtraBalance < claimCost ? _relayerExtraBalance : claimCost;
        vm.deal(address(gasTank), _relayCost + claimCost);
        uint256 claimerBalanceBefore = address(this).balance;

        vm.expectEmit(address(gasTank));
        emit IGasTank.Claimed(_originMsgHash, _relayer, _gasProvider, address(this), _relayCost, claimCost);
        gasTank.claim(id, _gasProvider, payload);

        // Assertions
        for (uint256 i; i < destinationMessageHashes.length; i++) {
            assertTrue(
                gasTank.authorizedMessages(_gasProvider, destinationMessageHashes[i]),
                "GasTank should have authorized the destination message"
            );
        }
        assertEq(gasTank.balanceOf(_gasProvider), _relayerExtraBalance - claimCost, "GasTank balance should be 0");
        assertTrue(gasTank.claimed(_originMsgHash), "GasTank should have claimed the root message");
        assertEq(_relayer.balance, _relayCost, "GasTank should have compensated relayer");
        assertEq(address(this).balance, claimerBalanceBefore + claimCost, "GasTank should have paid the claim cost");
    }
}
