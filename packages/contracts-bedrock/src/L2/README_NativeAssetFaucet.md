# NativeAssetFaucet - CGT Devnet Faucet

Simple faucet contract for Custom Gas Token (CGT) devnets that allows both permissionless and owner-controlled token minting.

## Overview

The NativeAssetFaucet is deployed to L2 via deposit transactions from L1, using the CREATE2 deployer predeploy for deterministic addresses. It provides two ways to mint CGT tokens:

1. **Permissionless Claims**: Any user can claim a fixed amount of tokens once per block
2. **Owner Minting**: The owner can mint any amount to any address

## Deployment

### Prerequisites

- Running op-up devnet with CGT mode enabled
- Foundry installed

### Step 1: Get the Portal Address

When you start op-up, it prints the Test Account address and private key. This account is both pre-funded on L1 and is the LiquidityController owner.

```bash
# Get the OptimismPortal address
L1_CDM=$(cast call 0x4200000000000000000000000000000000000007 "l1CrossDomainMessenger()(address)" --rpc-url http://127.0.0.1:8545)
PORTAL=$(cast call $L1_CDM "portal()(address)" --rpc-url http://127.0.0.1:8544)
echo "Portal: $PORTAL"
```

### Step 2: Run the Deploy Script

Use the Test Account credentials printed by op-up:

```bash
cd packages/contracts-bedrock

PORTAL=<PORTAL_ADDRESS> \
FAUCET_OWNER=<TEST_ACCOUNT_ADDRESS> \
PERMISSIONLESS_AMOUNT=1000000000000000000 \
PRIVATE_KEY=<TEST_ACCOUNT_PRIVATE_KEY> \
forge script scripts/DeployNativeAssetFaucet.s.sol --rpc-url http://127.0.0.1:8544 --broadcast
```

The script will output the computed faucet address. Wait ~15 seconds for L2 to process the deposit transactions.

### Step 3: Verify Deployment

```bash
FAUCET=<COMPUTED_FAUCET_ADDRESS>

# Check faucet has code
cast code $FAUCET --rpc-url http://127.0.0.1:8545

# Check faucet is authorized as minter
cast call 0x420000000000000000000000000000000000002a "minters(address)(bool)" $FAUCET --rpc-url http://127.0.0.1:8545
```

## Usage

### Permissionless Claim

Any user can claim tokens once per block:

```bash
# Claim tokens to a recipient
cast send $FAUCET "claim(address)" <RECIPIENT> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANY_PRIVATE_KEY>

# Check balance
cast balance <RECIPIENT> --rpc-url http://127.0.0.1:8545
```

### Owner Mint

The owner can mint any amount to any address:

```bash
cast send $FAUCET "mint(address,uint256)" <RECIPIENT> <AMOUNT> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <OWNER_PRIVATE_KEY>
```

### Claim from L1 (via Portal)

You can trigger a claim from L1 using a deposit transaction:

```bash
# Encode the claim call
CALLDATA=$(cast calldata "claim(address)" <RECIPIENT>)

# Send deposit transaction to the portal
cast send $PORTAL \
  "depositTransaction(address,uint256,uint64,bool,bytes)" \
  $FAUCET \
  0 \
  200000 \
  false \
  $CALLDATA \
  --rpc-url http://127.0.0.1:8544 \
  --private-key <PRIVATE_KEY>
```

Wait ~15-30 seconds for L2 to process the deposit transaction, then check the recipient's balance.

> **Note**: The gas limit of 200000 is required because `claim` uses ~175k gas due to minting via the LiquidityController.

### Adjust Permissionless Amount

The owner can change the per-block claim amount:

```bash
cast send $FAUCET "setPermissionlessAmount(uint256)" <NEW_AMOUNT> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <OWNER_PRIVATE_KEY>
```

## Contract Details

### Addresses

- **NativeAssetFaucet**: Deployed via CREATE2 (address depends on owner and permissionless amount)
- **LiquidityController**: `0x420000000000000000000000000000000000002a`
- **Create2Deployer**: `0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2`

### Functions

| Function | Access | Description |
|----------|--------|-------------|
| `claim(address _to)` | Anyone | Claim permissionless amount (once per block per recipient) |
| `mint(address _to, uint256 _amount)` | Owner only | Mint any amount to any address |
| `setPermissionlessAmount(uint256 _amount)` | Owner only | Update the permissionless claim amount |

### Errors

| Error | Description |
|-------|-------------|
| `NativeAssetFaucet_Unauthorized` | Caller is not the owner |
| `NativeAssetFaucet_BlockLimitReached` | Recipient already claimed this block |

## Architecture

```
L1                                      L2
┌──────────────────────┐               ┌──────────────────────────┐
│   DeployScript       │               │                          │
│   (forge script)     │               │                          │
└──────────┬───────────┘               │                          │
           │                           │                          │
           │ depositTransaction()      │                          │
           ▼                           │                          │
┌──────────────────────┐               │  ┌────────────────────┐  │
│   OptimismPortal2    │───deposit────►│  │  Create2Deployer   │  │
└──────────────────────┘               │  │  (0x13b0D85...)    │  │
                                       │  └─────────┬──────────┘  │
                                       │            │ deploy()    │
                                       │            ▼             │
                                       │  ┌────────────────────┐  │
                                       │  │ NativeAssetFaucet  │  │
                                       │  │   - claim()        │  │
                                       │  │   - mint()         │  │
                                       │  └─────────┬──────────┘  │
                                       │            │ mint()      │
                                       │            ▼             │
                                       │  ┌────────────────────┐  │
                                       │  │LiquidityController │  │
                                       │  │  (0x42...002a)     │  │
                                       │  └────────────────────┘  │
                                       └──────────────────────────┘
```

## Important Notes

1. **CGT Mode Required**: This faucet only works when Custom Gas Token mode is enabled
2. **Rate Limiting**: The claim rate limit is per recipient address (`_to`), not per caller
3. **Immutable Owner**: Once deployed, the owner cannot be changed
4. **CREATE2 Deployer**: Uses the OP Stack Create2Deployer predeploy at `0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2`

## Files

- `src/L2/NativeAssetFaucet.sol` - Faucet contract
- `scripts/DeployNativeAssetFaucet.s.sol` - Deployment script
