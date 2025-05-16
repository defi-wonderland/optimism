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
        bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address relayer, address txOrigin, uint256 cost
    );

    error MaxDepositExceeded();
    error InvalidOrigin();
    error InvalidPayload();
    error InvalidRootMessage();
    error InsufficientBalance();
    error AlreadyClaimed();

    uint256 public constant MAX_DEPOSIT = 0.01 ether;
    // TODO: Calculate claim overhead
    uint256 public constant CLAIM_OVERHEAD = 100_000;

    IL2ToL2CrossDomainMessenger public constant MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    mapping(address => uint256) public balanceOf;
    mapping(bytes32 => bool) public claimed;
    mapping(bytes32 => bool) public flaggedMessages;

    function deposit() external payable {
        uint256 newBalance = balanceOf[msg.sender] + msg.value;
        if (msg.value > MAX_DEPOSIT) revert MaxDepositExceeded();

        balanceOf[msg.sender] = newBalance;
        emit Deposit(msg.sender, msg.value);
    }

    function flag(bytes32 rootMessageHash) external {
        flaggedMessages[rootMessageHash] = true;
        emit Flagged(rootMessageHash);
    }

    function claim(Identifier calldata id, bytes calldata payload) external {
        // Ensure the origin is the messenger
        if (id.origin != address(MESSENGER)) revert InvalidOrigin();

        // Decode the receipt
        if (bytes32(payload[:32]) != RelayedMessageGasReceipt.selector) revert InvalidPayload();
        (bytes32 msgHash, bytes32 rootMsgHash, address relayer, address txOrigin, uint256 relayCost) =
            decodeGasReceiptPayload(payload);

        // Ensure the message is flagged
        if (!flaggedMessages[rootMsgHash]) revert InvalidRootMessage();

        // Ensure unclaimed
        if (claimed[msgHash]) revert AlreadyClaimed();

        // Compute total cost (adding the overhead of this claim)
        uint256 claimCost = CLAIM_OVERHEAD * block.basefee;
        uint256 cost = relayCost + claimCost;
        // TODO: Make it more flexible so to allow partial repayment, but tracking the claim as partially repaid
        if (balanceOf[txOrigin] < cost) revert InsufficientBalance();

        // Ensure the original outbound message was sent from this chain
        if (!MESSENGER.sentMessages(rootMsgHash)) revert InvalidRootMessage();

        // Validate the message
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(id, keccak256(payload));

        // Update the balance and mark the claim
        balanceOf[txOrigin] -= cost;
        claimed[msgHash] = true;

        // Send the funds to the relayer
        // TODO: Better to do a low-level call?
        new SafeSend{ value: cost }(payable(relayer));

        emit Claimed(msgHash, relayer, cost);
    }

    // TODO: code logic
    function decodeGasReceiptPayload(bytes calldata payload)
        public
        pure
        returns (bytes32 msgHash, bytes32 rootMsgHash, address relayer, address txOrigin, uint256 relayCost)
    {
        // Decode Topics
        (msgHash, rootMsgHash, relayer) = abi.decode(payload[32:128], (bytes32, bytes32, address));

        // Decode Data
        (txOrigin, relayCost) = abi.decode(payload[128:], (address, uint256));
    }

    // TODO: Out of scope for PoC
    //    function flagAndDeposit(bytes32 rootMessageHash) external payable { }
    // function withdraw(bytes32 rootMessageHash) external {}
}

// 1.  send message on l1 and check context is good
// 2.  relay message on l2 and sent message back to l1 to claim
// 3. check gas consumption properly reflects the relay cost
