// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Identifier } from "./ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger, Identifier as RelayID } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

interface IGasTank {
    // Structs
    struct Withdrawal {
        uint256 timestamp;
        uint256 amount;
    }
    // Events

    event Flagged(bytes32 indexed rootMsgHash, address indexed gasProvider);
    event Claimed(
        bytes32 indexed msgHash,
        address indexed relayer,
        address indexed gasProvider,
        bytes32 rootMsgHash,
        uint256 amount
    );
    event Deposit(address indexed depositor, uint256 amount);
    event RelayedMessageGasReceipt(
        bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address indexed relayer, uint256 gasCost
    );
    event WithdrawalInitiated(address indexed from, uint256 amount);
    event WithdrawalFinalized(address indexed from, address indexed to, uint256 amount);

    // Errors
    error MaxDepositExceeded();
    error InvalidOrigin();
    error InvalidPayload();
    error InvalidRootMessage();
    error InsufficientBalance();
    error AlreadyClaimed();
    error InvalidPayer();
    error WithdrawPending();
    error InvalidLength();

    // Constants
    function MAX_DEPOSIT() external pure returns (uint256);
    function WITHDRAWAL_DELAY() external pure returns (uint256);
    function CLAIM_OVERHEAD() external pure returns (uint256);
    function MESSENGER() external pure returns (IL2ToL2CrossDomainMessenger);

    // State Variables
    function balanceOf(address) external view returns (uint256);
    function withdrawals(address) external view returns (uint256 timestamp, uint256 amount);
    function claimed(bytes32) external view returns (bool);
    function flaggedMessages(address, bytes32) external view returns (bool);

    // Functions
    function deposit(address _to) external payable;
    function initiateWithdrawal(uint256 amount) external;
    function finalizeWithdrawal(address to) external;
    function flag(bytes32 rootMessageHash) external;
    function relayMessage(RelayID[] calldata _id, bytes[] calldata _sentMessage) external;
    function claim(Identifier calldata id, address gasProvider, bytes calldata payload) external;
    function decodeGasReceiptPayload(bytes calldata payload)
        external
        pure
        returns (bytes32 msgHash, bytes32 rootMsgHash, address relayer, uint256 relayCost);
}
