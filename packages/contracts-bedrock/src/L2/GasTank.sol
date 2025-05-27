// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeSend } from "src/universal/SafeSend.sol";

contract GasTank {
    event Flagged(bytes32 rootMessageHash);
    event Claimed(bytes32 msgHash, address relayer, uint256 amount);
    event Deposit(address depositor, uint256 amount);
    event RelayedMessageGasReceipt(
        bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address relayer, uint256 cost
    );
    event WithdrawalInitiated(address indexed from, uint256 amount);
    event WithdrawalFinalized(address indexed from, address indexed to, uint256 amount);

    error MaxDepositExceeded();
    error InvalidOrigin();
    error InvalidPayload();
    error InvalidRootMessage();
    error InsufficientBalance();
    error AlreadyClaimed();
    error InvalidPayer();
    error WithdrawPending();
    error WithdrawDoesNotExist();

    uint256 public constant MAX_DEPOSIT = 0.01 ether;
    uint256 public constant WITHDRAWAL_DELAY = 1 days;
    // TODO: Calculate claim overhead
    uint256 public constant CLAIM_OVERHEAD = 100_000;

    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    struct Withdrawal {
        uint256 timestamp;
        uint256 amount;
    }

    mapping(address => uint256) public balanceOf;
    mapping(address gasProvider => Withdrawal) public withdrawals;
    mapping(bytes32 => bool) public claimed;
    mapping(address gasProvider => mapping(bytes32 msgHash => bool)) public flaggedMessages;

    // Deposit funds into the gas tank, from which the relayer can claim the repayment after relaying
    function deposit(address _to) external payable {
        uint256 newBalance = balanceOf[_to] + msg.value;

        if (newBalance > MAX_DEPOSIT) revert MaxDepositExceeded();

        balanceOf[_to] = newBalance;
        emit Deposit(_to, msg.value);
    }

    function initiateWithdrawal(uint256 amount) external {
        // Ensure the caller has enough balance
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        // Record the pending withdrawal
        withdrawals[msg.sender] = Withdrawal({
            timestamp: block.timestamp,
            amount: amount
        });

        // Emit an event for the withdrawal initiation
        emit WithdrawalInitiated(msg.sender, amount);
    }

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

    // Flag a message into the gas tank so the relayer is aware of it, and can claim the funds after relaying
    function flag(bytes32 rootMessageHash) external {
        flaggedMessages[msg.sender][rootMessageHash] = true;
        emit Flagged(rootMessageHash);
    }

    // Claim repayment for a relayed message
    function claim(Identifier calldata id, address gasProvider, bytes calldata payload) external {
        // Ensure the origin is the messenger
        if (id.origin != address(MESSENGER)) revert InvalidOrigin();

        // Decode the receipt
        if (bytes32(payload[:32]) != RelayedMessageGasReceipt.selector) revert InvalidPayload();
        (bytes32 msgHash, bytes32 rootMsgHash, address relayer, uint256 relayCost) =
            decodeGasReceiptPayload(payload);

        // Ensure the message is flagged for relaying
        if (!flaggedMessages[gasProvider][rootMsgHash]) revert InvalidPayer();

        // Ensure unclaimed
        if (claimed[msgHash]) revert AlreadyClaimed();

        // Compute total cost (adding the overhead of this claim)
        uint256 claimCost = CLAIM_OVERHEAD * block.basefee;
        uint256 cost = relayCost + claimCost;
        // TODO: Make it more flexible so to allow partial repayment, but tracking the claim as partially repaid
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

        emit Claimed(msgHash, relayer, cost);
    }

    // Decode the payload of the RelayedMessageGasReceipt event
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

    // TODO: Out of scope for PoC
    //    function flagAndDeposit(bytes32 rootMessageHash) external payable { }
    // function withdraw(bytes32 rootMessageHash) external {}
    // TODO: Add function to add authorized relayers only to withdraw from the gas tank (business logic)
}
