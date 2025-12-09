# Custom Gas Token Faucet

Deploy a NativeAssetFaucet on L2 via deposit transactions from L1. The faucet allows minting of the native asset (custom gas token) to recipients.

## Prerequisites

- The LiquidityController owner on L2 can be an EOA or a multisig (Safe)
- If EOA: the same address must have funds on L1 to execute the deployment script
- If Safe: the Safe's **aliased address** must be the LiquidityController owner on L2

## Contracts

| Contract | Description |
|----------|-------------|
| `NativeAssetFaucet.sol` | L2 contract that mints native asset to recipients |
| `FaucetDeployer.sol` | L1 helper for deploying via Safe delegatecall (optional) |
| `DeployNativeAssetFaucet.s.sol` | Forge script to deploy and authorize the faucet |
| `DeployFaucetDeployer.s.sol` | Forge script to deploy the FaucetDeployer helper |
| `MintNativeAsset.s.sol` | Forge script to mint native asset from L1 (for admins) |

## Deployment

### Step 1: Get the Portal address

```bash
L1_MESSENGER=$(cast call 0x4200000000000000000000000000000000000007 "otherMessenger()(address)" --rpc-url <L2_RPC_URL>)
PORTAL=$(cast call $L1_MESSENGER "portal()(address)" --rpc-url <L1_RPC_URL>)
echo "Portal: $PORTAL"
```

### Step 2: Verify LiquidityController owner

```bash
cast call 0x420000000000000000000000000000000000002a "owner()(address)" --rpc-url <L2_RPC_URL>
```

This address must match the account that will execute the deployment script.

### Step 3: Deploy the faucet

Run the script with the LiquidityController owner's private key:

```bash
forge script scripts/deploy/cgt-faucet/DeployNativeAssetFaucet.s.sol \
  --sig "run(address,address,uint256,uint64,string)" \
  <PORTAL_ADDRESS> \
  <FAUCET_OWNER> \
  <PERMISSIONLESS_AMOUNT> \
  <GAS_LIMIT> \
  <SALT_SEED> \
  --rpc-url <L1_RPC_URL> \
  --private-key <LC_OWNER_PRIVATE_KEY> \
  --broadcast
```

Parameters:
- `PORTAL_ADDRESS`: OptimismPortal2 address on L1 (from Step 1)
- `FAUCET_OWNER`: Address that will own the faucet (can call `mint()` without limits)
- `PERMISSIONLESS_AMOUNT`: Amount claimable per `claim()` call (in wei)
- `GAS_LIMIT`: Gas limit for L2 deposit transactions (recommended: 500000)
- `SALT_SEED`: Salt for deterministic CREATE2 deployment (e.g., "Faucet")

Example:
```bash
forge script scripts/deploy/cgt-faucet/DeployNativeAssetFaucet.s.sol \
  --sig "run(address,address,uint256,uint64,string)" \
  0x5cB3C128A2Ad79fb3d675038dAcFf885ad7aa9d1 \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  1000000000000000000 \
  500000 \
  "Faucet" \
  --rpc-url http://127.0.0.1:8455 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### Step 4: Verify deployment

Wait ~10 seconds for the deposit transactions to be processed on L2, then verify:

```bash
FAUCET=<FAUCET_ADDRESS_FROM_SCRIPT_OUTPUT>

# Check faucet has code
cast code $FAUCET --rpc-url <L2_RPC_URL>

# Check faucet owner
cast call $FAUCET "owner()(address)" --rpc-url <L2_RPC_URL>

# Check faucet is authorized as minter
cast call 0x420000000000000000000000000000000000002a "minters(address)(bool)" $FAUCET --rpc-url <L2_RPC_URL>
```

## Usage

### Permissionless claim

Anyone can call `claim()` to receive the `permissionlessAmount`:

```bash
cast send $FAUCET "claim(address)" <RECIPIENT> \
  --private-key <ANY_PRIVATE_KEY> \
  --rpc-url <L2_RPC_URL>
```

Note: There is a rate limit of one claim per block per recipient.

### Owner mint

The faucet owner can mint any amount without limits:

```bash
cast send $FAUCET "mint(address,uint256)" <RECIPIENT> <AMOUNT> \
  --private-key <FAUCET_OWNER_PRIVATE_KEY> \
  --rpc-url <L2_RPC_URL>
```

### Update permissionless amount

The faucet owner can update the permissionless claim amount:

```bash
cast send $FAUCET "setPermissionlessAmount(uint256)" <NEW_AMOUNT> \
  --private-key <FAUCET_OWNER_PRIVATE_KEY> \
  --rpc-url <L2_RPC_URL>
```

## Admin Minting from L1

When the faucet owner doesn't have gas on L2, they can mint from L1 using the `MintNativeAsset` script:

```bash
forge script scripts/deploy/cgt-faucet/MintNativeAsset.s.sol \
  --sig "run(address,address,address,uint256,uint64)" \
  <PORTAL_ADDRESS> \
  <FAUCET_ADDRESS> \
  <RECIPIENT_ADDRESS> \
  <AMOUNT_IN_WEI> \
  <GAS_LIMIT> \
  --rpc-url <L1_RPC_URL> \
  --private-key <FAUCET_OWNER_PRIVATE_KEY> \
  --broadcast
```

Example (mint 10 tokens to a recipient):
```bash
forge script scripts/deploy/cgt-faucet/MintNativeAsset.s.sol \
  --sig "run(address,address,address,uint256,uint64)" \
  0x5cB3C128A2Ad79fb3d675038dAcFf885ad7aa9d1 \
  0x0C3348692E1752D309F975F4423B21F44878A54C \
  0x1111111111111111111111111111111111111111 \
  10000000000000000000 \
  100000 \
  --rpc-url http://127.0.0.1:8455 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

This sends a deposit transaction from L1 that calls `mint()` on the faucet. The transaction must be signed by the faucet owner.

## Architecture

```
L1                                              L2
┌──────────────────┐                           ┌─────────────────────┐
│                  │                           │                     │
│  EOA (LC Owner)  │──depositTransaction──────►│  NativeAssetFaucet  │
│                  │                           │  (CREATE2 deployed) │
└──────────────────┘                           └──────────┬──────────┘
                                                          │
                                               authorized │ mint()
                                                          ▼
                                               ┌─────────────────────┐
                                               │ LiquidityController │
                                               │ (0x42...002a)       │
                                               └─────────────────────┘
```

The deployment script sends two deposit transactions from L1:
1. Deploy NativeAssetFaucet via CREATE2
2. Authorize the faucet as a minter in LiquidityController

Both transactions must come from the LiquidityController owner for the authorization to succeed.

## Deployment with Multisig (Safe)

When the LiquidityController owner is a Safe's aliased address, use the `FaucetDeployer` helper contract.

### Step 1: Calculate the aliased address

The L2 owner must be the Safe's aliased address:

```
L2_owner = L1_Safe_address + 0x1111000000000000000000000000000000001111
```

```bash
python3 -c "
safe = int('<L1_SAFE_ADDRESS>', 16)
offset = int('0x1111000000000000000000000000000000001111', 16)
aliased = (safe + offset) % (2**160)
print(f'Safe aliased (L2): {hex(aliased)}')"
```

Verify it matches the LiquidityController owner:
```bash
cast call 0x420000000000000000000000000000000000002a "owner()(address)" --rpc-url <L2_RPC_URL>
```

### Step 2: Deploy FaucetDeployer on L1

```bash
forge script scripts/deploy/cgt-faucet/DeployFaucetDeployer.s.sol \
  --sig "run(address)" \
  <PORTAL_ADDRESS> \
  --rpc-url <L1_RPC_URL> \
  --private-key <ANY_FUNDED_PRIVATE_KEY> \
  --broadcast
```

Save the deployed `FAUCET_DEPLOYER` address from the output.

### Step 3: Execute via Safe delegatecall

From the Safe UI or CLI, execute a delegatecall to the FaucetDeployer:

**Target:** `<FAUCET_DEPLOYER_ADDRESS>`
**Operation:** `delegatecall`
**Function:** `deployAndAuthorize(address,uint256,uint64)`
**Parameters:**
- `_faucetOwner`: Address that will own the faucet
- `_permissionlessAmount`: Amount claimable per call (in wei)
- `_gasLimit`: Gas limit for L2 transactions (recommended: 500000)

Example calldata:
```bash
cast calldata "deployAndAuthorize(address,uint256,uint64)" \
  <FAUCET_OWNER> \
  1000000000000000000 \
  500000
```

### Step 4: Verify deployment

Same as EOA deployment - wait for L2 to process and verify the faucet is deployed and authorized.

### Minting via Safe

The faucet owner (if it's a Safe) can mint tokens using the FaucetDeployer:

**Target:** `<FAUCET_DEPLOYER_ADDRESS>`
**Operation:** `delegatecall`
**Function:** `mint(address,address,uint256,uint64)`
**Parameters:**
- `_faucet`: NativeAssetFaucet address on L2
- `_to`: Recipient address
- `_amount`: Amount to mint
- `_gasLimit`: Gas limit (recommended: 100000)
