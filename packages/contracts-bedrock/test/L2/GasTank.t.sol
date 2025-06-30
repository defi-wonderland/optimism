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
import { IGasPriceOracle } from "interfaces/L2/IGasPriceOracle.sol";

contract GasTankTest is Test {
    using stdStorage for StdStorage;

    GasTank public gasTank;
    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    IGasPriceOracle public constant GAS_PRICE_ORACLE = IGasPriceOracle(Predeploys.GAS_PRICE_ORACLE);

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

        assertEq(
            gasTank.balanceOf(address(this)), _depositAmount, "Depositor balance should match the deposited amount"
        );
    }

    function testFuzz_initiateWithdrawal_succeeds(uint256 _withdrawalAmount) external {
        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalInitiated(address(this), _withdrawalAmount);
        gasTank.initiateWithdrawal(_withdrawalAmount);

        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(amount, _withdrawalAmount, "GasTank should have recorded the pending withdrawal amount");
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
        // Assumptions
        vm.assume(_to != address(this) && _to != address(gasTank));

        // Setting storage
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

        // Call finalizeWithdrawal
        uint256 toBalanceBefore = _to.balance;
        vm.expectEmit(address(gasTank));
        emit IGasTank.WithdrawalFinalized(address(this), _to, withdrawableAmount);
        gasTank.finalizeWithdrawal(_to);

        // Assertions
        (uint256 timestamp, uint256 amount) = gasTank.withdrawals(address(this));
        assertEq(timestamp, 0, "Withdrawal timestamp should be deleted");
        assertEq(amount, 0, "Withdrawal amount should be deleted");
        assertEq(
            gasTank.balanceOf(address(this)),
            _balance - withdrawableAmount,
            "Depositor balance should be deducted after finalizing the withdrawal"
        );
        assertEq(
            _to.balance, toBalanceBefore + withdrawableAmount, "To address should have received the withdrawn amount"
        );
    }

    function testFuzz_authorizeClaim_succeeds(bytes32 _messageHash) external {
        bytes32[] memory _messageHashes = new bytes32[](1);
        _messageHashes[0] = _messageHash;

        vm.expectEmit(address(gasTank));
        emit IGasTank.AuthorizedClaims(address(this), _messageHashes);
        gasTank.authorizeClaim(_messageHash);

        assertTrue(
            gasTank.authorizedMessages(address(this), _messageHash), "GasTank should have flagged caller's message"
        );
    }

    struct TestParams {
        uint256 baseFee;
        uint256 L1BaseCost;
        uint256 numHashes;
        address sender;
        uint256 srcChainId;
        uint256 dstChainId;
        address target;
        uint256 nonceBefore;
        bytes dstCallData;
    }

    struct TestData {
        bytes32 messageHash;
        Identifier id;
        uint256 totalGasCost;
        bytes sentMessage;
        bytes relayCallData;
    }

    function _prepareTestData(TestParams memory params) private view returns (TestData memory) {
        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage(
            params.dstChainId, params.srcChainId, params.nonceBefore, params.sender, params.target, params.dstCallData
        );

        Identifier memory id;
        id.chainId = params.srcChainId;
        id.origin = address(gasTank);

        uint256 totalGasCost = params.baseFee
            * (
                (4_423 + (35_000 + (420 * params.numHashes) + (params.numHashes ** 2) / 512))
                    + (34_205 + (418 * params.numHashes))
            ) + params.L1BaseCost;

        bytes memory sentMessage = abi.encodePacked(
            abi.encode(
                IL2ToL2CrossDomainMessenger.SentMessage.selector, params.dstChainId, params.target, params.nonceBefore
            ),
            abi.encode(params.sender, params.dstCallData)
        );

        bytes memory relayCallData =
            abi.encodeWithSignature("relayMessage((address,uint256,uint256,uint256,uint256),bytes)", id, sentMessage);

        return TestData({
            messageHash: messageHash,
            id: id,
            totalGasCost: totalGasCost,
            sentMessage: sentMessage,
            relayCallData: relayCallData
        });
    }

    function _setupOracleMockCalls(TestParams memory params, TestData memory testData) private {
        vm.expectCall(
            address(Predeploys.GAS_PRICE_ORACLE), abi.encodeWithSignature("getL1Fee(bytes)", testData.relayCallData)
        );
        vm.mockCall(
            address(Predeploys.GAS_PRICE_ORACLE),
            abi.encodeWithSignature("getL1Fee(bytes)", testData.relayCallData),
            abi.encode(params.L1BaseCost)
        );
    }

    function _setupNestedMessagesMockCalls(TestParams memory params) private returns (bytes32[] memory) {
        bytes32[] memory nestedMessageHashes = new bytes32[](params.numHashes);
        for (uint256 i; i < params.numHashes; i++) {
            vm.expectCall(
                address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
                abi.encodeWithSignature("sentMessages(uint256)", params.nonceBefore + 1 + i)
            );
            vm.mockCall(
                address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER),
                abi.encodeWithSignature("sentMessages(uint256)", params.nonceBefore + 1 + i),
                abi.encode("")
            );
            nestedMessageHashes[i] = keccak256(abi.encode(params.nonceBefore + 1 + i));
        }
        return nestedMessageHashes;
    }

    function _setupMessengerMocks(TestParams memory params) private {
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(uint240(params.nonceBefore), uint240(1));
        mocks[1] = abi.encode(uint240(params.nonceBefore + params.numHashes), uint240(1));
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
    }

    function testFuzz_relayMessage_succeeds(
        uint256 _baseFee,
        uint256 _L1BaseCost,
        uint256 _numHashes,
        address _sender,
        uint256 _srcChainId,
        uint256 _dstChainId,
        address _target,
        uint256 _nonceBefore,
        bytes memory _dstCallData
    )
        external
    {
        TestParams memory params = TestParams({
            baseFee: bound(_baseFee, 1, type(uint256).max / 1_000_000),
            L1BaseCost: bound(_L1BaseCost, 0, type(uint256).max / 1_000_000),
            numHashes: bound(_numHashes, 0, 100),
            sender: _sender,
            srcChainId: _srcChainId,
            dstChainId: _dstChainId,
            target: _target,
            nonceBefore: bound(_nonceBefore, 0, 100_000_000),
            dstCallData: _dstCallData
        });

        vm.fee(params.baseFee);

        TestData memory testData = _prepareTestData(params);

        _setupMessengerMocks(params);

        bytes32[] memory nestedMessageHashes = _setupNestedMessagesMockCalls(params);

        _setupOracleMockCalls(params, testData);

        // Call relayMessage
        vm.expectEmit(true, true, true, false, address(gasTank)); // TODO calculate based on numHashes
        emit IGasTank.RelayedMessageGasReceipt(
            testData.messageHash, address(this), testData.totalGasCost, nestedMessageHashes
        );
        gasTank.relayMessage(testData.id, testData.sentMessage);
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
        bytes32 _messageHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider
    )
        external
    {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory nestedMessageHashes = new bytes32[](1);
        nestedMessageHashes[0] = _destinationMsgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _messageHash, _relayer),
            abi.encode(_relayCost, nestedMessageHashes)
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
        bytes32 _messageHash,
        bytes32 _destinationMsgHash,
        address _relayer,
        uint256 _relayCost,
        address _gasProvider
    )
        external
    {
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory nestedMessageHashes = new bytes32[](1);
        nestedMessageHashes[0] = _destinationMsgHash;
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _messageHash, _relayer),
            abi.encode(_relayCost, nestedMessageHashes)
        );

        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _messageHash
        ).checked_write(true);

        stdstore.target(address(gasTank)).sig("claimed(bytes32)").with_key(_messageHash).checked_write(true);

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
        bytes32 _messageHash,
        bytes32[] memory _destinationMsgHashes,
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

        bytes32[] memory nestedMessageHashes = new bytes32[](_destinationMsgHashes.length);
        for (uint256 i; i < _destinationMsgHashes.length; i++) {
            nestedMessageHashes[i] = _destinationMsgHashes[i];
        }
        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _messageHash, _relayer),
            abi.encode(_relayCost, nestedMessageHashes)
        );

        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _messageHash
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
        vm.expectEmit(address(gasTank));
        emit IGasTank.AuthorizedClaims(_gasProvider, nestedMessageHashes);
        gasTank.claim(id, _gasProvider, payload);
    }

    function testFuzz_claim_succeeds(
        uint256 _baseFee,
        uint256 _L1BaseFee,
        bytes32[] memory _destinationMsgHashes,
        bytes32 _messageHash,
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
            _L1BaseFee = bound(_L1BaseFee, 1, maxBaseFee);
            vm.fee(_baseFee);
            _relayCost = bound(_relayCost, 1, maxDeposit - _relayerExtraBalance);
        }

        // Setting storage
        stdstore.target(address(gasTank)).sig("balanceOf(address)").with_key(_gasProvider).checked_write(
            _relayCost + _relayerExtraBalance
        );
        stdstore.target(address(gasTank)).sig("authorizedMessages(address,bytes32)").with_key(_gasProvider).with_key(
            _messageHash
        ).checked_write(true);

        // Prepare call data
        Identifier memory id;
        id.origin = address(gasTank);

        bytes32[] memory nestedMessageHashes = new bytes32[](_destinationMsgHashes.length);
        for (uint256 i; i < _destinationMsgHashes.length; i++) {
            nestedMessageHashes[i] = _destinationMsgHashes[i];
        }

        bytes memory payload = abi.encodePacked(
            abi.encode(IGasTank.RelayedMessageGasReceipt.selector, _messageHash, _relayer),
            abi.encode(_relayCost, nestedMessageHashes)
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
        bytes memory claimCall = abi.encodeWithSignature(
            "claim((address,uint256,uint256,uint256,uint256),address,bytes)", id, _gasProvider, payload
        );
        vm.mockCall(
            address(GAS_PRICE_ORACLE), abi.encodeWithSignature("getL1Fee(bytes)", claimCall), abi.encode(_L1BaseFee)
        );
        vm.expectCall(address(GAS_PRICE_ORACLE), abi.encodeWithSignature("getL1Fee(bytes)", claimCall));

        // Call claim
        uint256 claimCost = gasTank.claimOverhead(_destinationMsgHashes.length, _baseFee, claimCall);
        claimCost = _relayerExtraBalance < claimCost ? _relayerExtraBalance : claimCost;
        vm.deal(address(gasTank), _relayCost + claimCost);
        uint256 claimerBalanceBefore = address(this).balance;

        vm.expectEmit(address(gasTank));
        emit IGasTank.AuthorizedClaims(_gasProvider, nestedMessageHashes);
        vm.expectEmit(address(gasTank));
        emit IGasTank.Claimed(_messageHash, _relayer, _gasProvider, address(this), _relayCost, claimCost);
        gasTank.claim(id, _gasProvider, payload);

        // Assertions
        for (uint256 i; i < nestedMessageHashes.length; i++) {
            assertTrue(
                gasTank.authorizedMessages(_gasProvider, nestedMessageHashes[i]),
                "GasTank should have authorized the gas provider's destination message"
            );
        }
        assertEq(
            gasTank.balanceOf(_gasProvider),
            _relayerExtraBalance - claimCost,
            "Gas provider's balance should be deducted after claiming"
        );
        assertTrue(gasTank.claimed(_messageHash), "GasTank should have claimed the root message");
        assertEq(_relayer.balance, _relayCost, "GasTank should have compensated the relayer");
        assertEq(address(this).balance, claimerBalanceBefore + claimCost, "GasTank should have paid the claimer");
    }
}
