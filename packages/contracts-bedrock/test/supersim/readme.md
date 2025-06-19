# Guide: Manually Relaying Interop Messages with `cast`

This guide describes how to form a message identifier and manually relay a `L2ToL2CrossDomainMessenger` cross-chain call. We will perform a `SuperchainERC20` interop transfer, as seen in the "First Steps" guide, but without using the auto-relayer.

## Table of Contents

- [Overview](#overview)
  - [Contracts Used](#contracts-used)
  - [High-Level Steps](#high-level-steps)
  - [Message Identifier](#message-identifier)
- [Steps](#steps)
  - [1. Start `supersim`](#1-start-supersim)
  - [2. Mint Tokens on Chain 901](#2-mint-tokens-to-transfer-on-chain-901)
  - [3. Initiate the Send Transaction on Chain 901](#3-initiate-the-send-transaction-on-chain-901)
  - [4. Get the Log from `L2ToL2CrossDomainMessenger`](#4-get-the-log-emitted-by-the-l2tol2crossdomainmessenger)
  - [5. Retrieve the Block Timestamp](#5-retrieve-the-block-timestamp-the-log-was-emitted-in)
  - [6. Prepare the Message Identifier & Payload](#6-prepare-the-message-identifier--payload)
  - [7. Construct the Access List](#7-construct-the-access-list-for-the-message)
  - [8. Send the Relay Transaction](#8-send-the-relay-message-transaction)
  - [9. Check the Balance on Chain 902](#9-check-the-balance-on-chain-902)
- [Alternatives](#alternatives)

---

## Overview

### Contracts Used

- **L2NativeSuperchainERC20**: `0x420beeF000000000000000000000000000000001`
- **L2ToL2CrossDomainMessenger**: `0x4200000000000000000000000000000000000023`

### High-Level Steps

Sending an interop message involves the following:

1.  **On Source Chain (OPChainA - 901):**

    - Invoke `L2NativeSuperchainERC20.sentERC20` to bridge funds, which leverages `L2ToL2CrossDomainMessenger.sendMessage`.
    - Retrieve the log identifier and message payload from the `SentMessage` event.

2.  **On Destination Chain (OPChainB - 902):**
    - Relay the message by calling `L2ToL2CrossDomainMessenger.relayMessage`.

### Message Identifier

A message identifier uniquely identifies a log emitted on a chain. The sequencer and the `CrossL2Inbox` use this identifier to perform invariant checks.

```solidity
struct Identifier {
    address origin;      // Contract that emitted the log
    uint256 blockNumber; // Block number of the log
    uint256 logIndex;    // Index of the log in the block
    uint256 timestamp;   // Timestamp of the block
    uint256 chainId;     // Chain ID where the log was emitted
}
```

---

## Steps

### 1. Start `supersim`

Ensure `supersim` is running without the auto-relayer.

```sh
supersim
```

### 2. Mint Tokens to Transfer on Chain 901

```sh
cast send 0x420beeF000000000000000000000000000000001 "mint(address,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 1000 --rpc-url http://127.0.0.1:9545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 3. Initiate the Send Transaction on Chain 901

```sh
cast send 0x4200000000000000000000000000000000000028 "sendERC20(address,address,uint256,uint256)" 0x420beeF0... 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 1000 902 --rpc-url http://127.0.0.1:9545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 4. Get the Log Emitted by the `L2ToL2CrossDomainMessenger`

```sh
cast logs --address 0x4200000000000000000000000000000000000023 --rpc-url http://127.0.0.1:9545
```

**Sample Output:**

```json
{
  "address": "0x4200000000000000000000000000000000000023",
  "blockHash": "0x311f8ccea3fc121aa3af18e0a87766ae56ed3f1d08cae91ec29f34a9919abcc0",
  "blockNumber": 14,
  "logIndex": 2,
  "transactionHash": "0x746a3e8a3a0ed0787367c3476269fa3050a2f9113637b563a4579fbc03efe5c4",
  "topics": [
    "0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320",
    "0x0000000000000000000000000000000000000000000000000000000000000386",
    "0x0000000000000000000000004200000000000000000000000000000000000028",
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  ],
  "data": "0x..."
}
```

### 5. Retrieve the Block Timestamp the Log Was Emitted In

```sh
cast block <BLOCK_HASH_FROM_STEP_4> --rpc-url http://127.0.0.1:9545
```

Note the `timestamp` from the output.

### 6. Prepare the Message Identifier & Payload

Use the values from the previous steps to build your identifier. The message payload is the concatenation of `[...topics, data]`.

### 7. Construct the Access List for the Message

An access list is required. `supersim` provides two custom admin RPC methods for this.

- **Method A: `admin_getAccessListByMsgHash`**
  Find the `msgHash` from the `supersim` logs and call the RPC.

  ```sh
  # Example msgHash from logs: 0xccff...
  cast rpc admin_getAccessListByMsgHash 0xccff97c17ef11d659d319cbc5780235ea03ef34b0fa34f40b208a9519f257379 --rpc-url http://localhost:8420
  ```

- **Method B: `admin_getAccessListForIdentifier`**
  Call the RPC with the full identifier and payload.
  ```sh
  cast rpc admin_getAccessListForIdentifier \
  '{
    "origin": "0x4200000000000000000000000000000000000023",
    "blockNumber": "14",
    "logIndex": "2",
    "timestamp": "1743801675",
    "chainId": "901",
    "payload": "0x..."
  }' --rpc-url http://localhost:8420
  ```

### 8. Send the Relay Message Transaction

Call `relayMessage` on the destination chain with the identifier, payload, and the `accessList` JSON from the previous step.

```sh
cast send 0x4200000000000000000000000000000000000023 \
    "relayMessage((address,uint256,uint256,uint256,uint256),bytes)" \
    "(0x4200..., 14, 2, 1743..., 901)" \
    0x... \
    --access-list '[{"address":"0x...","storageKeys":["0x..."]}]' \
    --rpc-url http://127.0.0.1:9546 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 9. Check the Balance on Chain 902

```sh
cast balance --erc20 0x420beeF000000000000000000000000000000001 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:9546
```

---

## Alternatives

Manually relaying is tedious. You can also:

- Use `supersim --interop.autorelay` for automatic relaying within `supersim`.
- Use `viem` bindings and actions if you are working in a TypeScript environment.
