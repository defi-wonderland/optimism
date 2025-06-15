// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Interfaces
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { IGasTank } from "interfaces/L2/IGasTank.sol";
import { IL2ToL2CrossDomainMessenger, Identifier } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

// Libraries
import { Encoding } from "src/libraries/Encoding.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeSend } from "src/universal/SafeSend.sol";

/// @title GasTank
/// @notice Allows users to deposit native tokens to compensate relayers for executing cross chain transactions
contract GasTank is IGasTank {
    using Encoding for uint256;

    /// @notice The maximum amount of funds that can be deposited into the gas tank
    uint256 public constant MAX_DEPOSIT = 0.01 ether;

    /// @notice The delay before a withdrawal can be finalized
    uint256 public constant WITHDRAWAL_DELAY = 7 days;

    /// @notice The gas cost of claiming a receipt
    uint256 public constant CLAIM_OVERHEAD = 100_000;

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
    /// @param amount The amount of funds to initiate a withdrawal for
    function initiateWithdrawal(uint256 amount) external {
        // Ensure the caller has enough balance
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        // Record the pending withdrawal
        withdrawals[msg.sender] = Withdrawal({ timestamp: block.timestamp, amount: amount });

        // Emit an event for the withdrawal initiation
        emit WithdrawalInitiated(msg.sender, amount);
    }

    /// @notice Finalizes a withdrawal of funds from the gas tank
    /// @param to The address to finalize the withdrawal to
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
    /// @param messageHash The hash of the message to flag
    function flag(bytes32 messageHash) external {
        flaggedMessages[msg.sender][messageHash] = true;
        emit Flagged(messageHash, msg.sender);
    }

    /// @notice Relays a message to the destination chain
    /// @param _id The identifier of the message
    /// @param _sentMessage The sent message event payload
    function relayMessage(Identifier calldata _id, bytes calldata _sentMessage) public {
        uint256 initialGas = gasleft();

        bytes32 originMessageHash = _getMessageHash(_id.chainId, _sentMessage);

        // Cache the Messenger nonce
        (uint240 nonceBefore,) = MESSENGER.messageNonce().decodeVersionedNonce();

        // Relay the message
        MESSENGER.relayMessage(_id, _sentMessage);

        // Get the difference between the initial nonce and the final nonce
        (uint240 nonceAfter,) = MESSENGER.messageNonce().decodeVersionedNonce();
        uint256 nonceDelta = nonceAfter - nonceBefore;

        bytes32[] memory destinationMessageHashes = new bytes32[](nonceDelta);

        for (uint256 j; j < nonceDelta; j++) {
            destinationMessageHashes[j] = MESSENGER.sentMessages(nonceBefore + j);
        }

        // Get the gas used
        uint256 gasUsed = (initialGas - gasleft()) + _gasReceiptEventOverhead(destinationMessageHashes.length);

        // Emit the event with the relationship between the origin message and the destination messages
        emit RelayedMessageGasReceipt(originMessageHash, msg.sender, _cost(gasUsed), destinationMessageHashes);
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
        (bytes32 originMessageHash, address relayer, uint256 relayCost, bytes32[] memory destinationMessageHashes) =
            decodeGasReceiptPayload(payload);

        // Ensure the message is flagged for relaying
        if (!flaggedMessages[gasProvider][originMessageHash]) {
            revert InvalidPayer();
        }

        // Ensure unclaimed
        if (claimed[originMessageHash]) revert AlreadyClaimed();

        // Compute total cost (adding the overhead of this claim)
        uint256 claimCost = CLAIM_OVERHEAD * block.basefee;
        uint256 cost = relayCost + claimCost;
        if (balanceOf[gasProvider] < cost) revert InsufficientBalance();

        // Validate the message
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(id, keccak256(payload));

        // Flag destination messages
        for (uint256 i; i < destinationMessageHashes.length; i++) {
            flaggedMessages[gasProvider][destinationMessageHashes[i]] = true;
        }

        // Update the balance and mark the claim
        balanceOf[gasProvider] -= cost;
        claimed[originMessageHash] = true;

        // Send the cost repayment back to the relayer
        new SafeSend{ value: cost }(payable(relayer));  // TODO How much gas cost? 2300?

        emit Claimed(originMessageHash, relayer, gasProvider, cost);
    }

    /// @notice Decodes the payload of the RelayedMessageGasReceipt event
    /// @param payload The payload of the event
    /// @return originMessageHash The hash of the relayed message
    /// @return relayer The address of the relayer
    /// @return relayCost The amount of native tokens expended on the relay
    /// @return destinationMessageHashes The hash of the root message
    function decodeGasReceiptPayload(bytes calldata payload)
        public
        pure
        returns (
            bytes32 originMessageHash,
            address relayer,
            uint256 relayCost,
            bytes32[] memory destinationMessageHashes
        )
    {
        // Decode Topics
        (originMessageHash, relayer, relayCost) = abi.decode(payload[32:128], (bytes32, address, uint256));

        // Decode Data
        destinationMessageHashes = abi.decode(payload[128:], (bytes32[]));
    }

    /// @notice Calculates the cost of a message relay.
    function _cost(uint256 _gasUsed) internal view returns (uint256) {
        return block.basefee * _gasUsed;
    }

    /// @notice Calculates the hash of a message
    /// @param _source The source chain ID
    /// @param _sentMessage The sent message
    /// @return messageHash The hash of the message
    function _getMessageHash(
        uint256 _source,
        bytes calldata _sentMessage
    )
        internal
        pure
        returns (bytes32 messageHash)
    {
        // Decode Topics
        (uint256 destination, address target, uint256 nonce) =
            abi.decode(_sentMessage[32:128], (uint256, address, uint256));

        // Decode Data
        (address sender, bytes memory message) = abi.decode(_sentMessage[128:], (address, bytes));

        // Get the current message hash
        messageHash = Hashing.hashL2toL2CrossDomainMessage(destination, _source, nonce, sender, target, message);
    }
    function _gasReceiptEventOverhead(uint256 numHashes) internal returns(uint256) {
        return 3_000 + 300 * numHashes;
    }
}
