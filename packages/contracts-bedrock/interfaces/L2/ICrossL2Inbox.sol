// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Identifier of a cross chain message.

struct Identifier {
    address origin;
    uint64 blockNumber;
    uint32 logIndex;
    uint64 timestamp;
    uint256 chainId;
}

interface ICrossL2Inbox {
    error NoExecutingDeposits();
    error NotInAccessList();

    event ExecutingMessage(bytes32 indexed msgHash, Identifier id);

    function version() external view returns (string memory);

    function validateMessage(Identifier calldata _id, bytes32 _msgHash) external;
}
