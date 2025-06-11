// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IGasTank } from "interfaces/L2/IGasTank.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeSend } from "src/universal/SafeSend.sol";
import { Hashing } from "src/libraries/Hashing.sol";

/// @title GasTank
/// @notice Allows users to deposit native tokens to compensate relayers for executing cross chain transactions
contract GasTank is IGasTank {
    /// @notice The maximum amount of funds that can be deposited into the gas tank
    uint256 public constant MAX_DEPOSIT = 0.01 ether;

    /// @notice The delay before a withdrawal can be finalized
    uint256 public constant WITHDRAWAL_DELAY = 7 days;

    /// @notice The gas cost of claiming a receipt
    uint256 public constant CLAIM_OVERHEAD = 100_000;

    /// @notice The gas overhead for the gas receipt event
    uint256 public constant GAS_RECEIPT_EVENT_OVERHEAD = 28772;

    /// @notice The cross domain messenger
    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    /// @notice The balance of each gas provider
    mapping(address gasProvider => uint256 balance) public balanceOf;

    /// @notice The current withdrawal of each gas provider
    mapping(address gasProvider => Withdrawal) public withdrawals;

    /// @notice The claimed messages
    mapping(bytes32 rootMsgHash => bool claimed) public claimed;

    /// @notice The flagged messages for relaying
    mapping(address gasProvider => mapping(bytes32 msgHash => bool flagged)) public flaggedMessages;

    /// @notice Deposits funds into the gas tank, from which the relayer can claim the repayment after relaying
    /// @param _to The address to deposit the funds to
    function deposit(address _to) external payable {
        uint256 newBalance = balanceOf[_to] + msg.value;

        if (newBalance > MAX_DEPOSIT) revert MaxDepositExceeded();

        balanceOf[_to] = newBalance;
        emit Deposit(_to, msg.value);
    }

    /// @notice Initiates a withdrawal of funds from the gas tank
    /// @param amount The amount of funds to withdraw
    function initiateWithdrawal(uint256 amount) external {
        // Ensure the caller has enough balance
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        // Record the pending withdrawal
        withdrawals[msg.sender] = Withdrawal({ timestamp: block.timestamp, amount: amount });

        // Emit an event for the withdrawal initiation
        emit WithdrawalInitiated(msg.sender, amount);
    }

    /// @notice Finalizes a withdrawal of funds from the gas tank
    /// @param to The address to withdraw the funds to
    function finalizeWithdrawal(address to) external {
        Withdrawal memory withdrawal = withdrawals[msg.sender];

        // Ensure the withdraw is not pending
        if (block.timestamp < withdrawal.timestamp + WITHDRAWAL_DELAY) revert WithdrawPending();

        // Update the balance
        uint256 amount = balanceOf[msg.sender] < withdrawal.amount ? balanceOf[msg.sender] : withdrawal.amount;
        balanceOf[msg.sender] -= amount;

        // Clear the pending withdrawal
        delete withdrawals[msg.sender];

        // Send the funds to the recipient
        new SafeSend{ value: amount }(payable(to));

        emit WithdrawalFinalized(msg.sender, to, amount);
    }

    /// @notice Flags a message into the gas tank so the relayer is aware of it, and can claim the funds after relaying
    /// @param originMsgHash The hash of the root message
    function flag(bytes32 originMsgHash) external {
        flaggedMessages[msg.sender][originMsgHash] = true;
        emit Flagged(originMsgHash, msg.sender);
    }

    function relayMessage(Identifier[] calldata _id, bytes[] calldata _sentMessage) public {
        uint256 length = _id.length;

        if (length != _sentMessage.length) revert InvalidLength();

        for (uint256 i; i < length; i++) {
            uint256 initialGas = gasleft();

            (bytes32 msgHash, bytes32 originMsgHash) = _getMessageData(_id[i].chainId, _sentMessage[i]);

            // Relay the message
            MESSENGER.relayMessage(_id[i], _sentMessage[i]);

            uint256 gasUsed = (initialGas - gasleft()) + GAS_RECEIPT_EVENT_OVERHEAD;
            emit RelayedMessageGasReceipt(msgHash, originMsgHash, msg.sender, _cost(gasUsed));
        }
    }

    /// @notice Claims repayment for a relayed message
    /// @param id The identifier of the message
    /// @param gasProvider The address of the gas provider
    /// @param payload The payload of the message
    function claim(Identifier calldata id, address gasProvider, bytes calldata payload) external {
        // Ensure the origin is a gas tank deployed with the same address on the destination chain
        if (id.origin != address(this)) revert InvalidOrigin();

        // Decode the receipt
        if (bytes32(payload[:32]) != RelayedMessageGasReceipt.selector) revert InvalidPayload();
        (bytes32 msgHash, bytes32 rootMsgHash, address relayer, uint256 relayCost) = decodeGasReceiptPayload(payload);

        // Ensure the message is flagged for relaying
        if (!flaggedMessages[gasProvider][rootMsgHash]) revert InvalidPayer();

        // Ensure unclaimed
        if (claimed[msgHash]) revert AlreadyClaimed();

        // Compute total cost (adding the overhead of this claim)
        uint256 claimCost = CLAIM_OVERHEAD * block.basefee;
        uint256 cost = relayCost + claimCost;
        if (balanceOf[gasProvider] < cost) revert InsufficientBalance();

        // Ensure the original outbound message was sent from this chain
        if (!MESSENGER.sentMessages(rootMsgHash)) revert InvalidRootMessage();

        // Validate the message
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(id, keccak256(payload));

        // Update the balance and mark the claim
        balanceOf[gasProvider] -= cost;
        claimed[msgHash] = true;

        // Send the cost repayment back to the relayer
        new SafeSend{ value: cost }(payable(relayer));

        emit Claimed(msgHash, relayer, gasProvider, rootMsgHash, cost);
    }

    /// @notice Decodes the payload of the RelayedMessageGasReceipt event
    /// @param payload The payload of the event
    /// @return msgHash The hash of the relayed message
    /// @return rootMsgHash The hash of the root message
    /// @return relayer The address of the relayer
    /// @return relayCost The amount of native tokens expended on the relay
    function decodeGasReceiptPayload(bytes calldata payload)
        public
        pure
        returns (bytes32 msgHash, bytes32 rootMsgHash, address relayer, uint256 relayCost)
    {
        // Decode Topics
        (msgHash, rootMsgHash, relayer) = abi.decode(payload[32:128], (bytes32, bytes32, address));

        // Decode Data
        relayCost = abi.decode(payload[128:], (uint256));
    }

    /// @notice Calculates the cost of a message relay.
    function _cost(uint256 _gasUsed) internal view returns (uint256) {
        return block.basefee * _gasUsed;
    }

    function _getMessageData(
        uint256 _source,
        bytes calldata _sentMessage
    )
        internal
        pure
        returns (bytes32 msgHash, bytes32 originMsgHash)
    {
        // Decode Topics
        (uint256 destination, address target, uint256 nonce) =
            abi.decode(_sentMessage[32:128], (uint256, address, uint256));

        // Decode Data
        (address sender, bytes memory message, bytes memory originContext) =
            abi.decode(_sentMessage[128:], (address, bytes, bytes));

        // Get the current message hash
        msgHash = Hashing.hashL2toL2CrossDomainMessage(
            Hashing.hashL2toL2CrossDomainMessagePayload(destination, _source, nonce, sender, target, message),
            originContext
        );

        // Recover the root message payload hash
        (, bytes32 contextMessagePayloadHash) = abi.decode(originContext, (uint8, bytes32));

        // Get the root message hash
        originMsgHash = Hashing.hashL2toL2CrossDomainMessage(contextMessagePayloadHash, originContext);
    }
}
