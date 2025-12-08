# FaucetDeployer POC - CGT Faucet via L1

This document describes the steps to deploy and configure the NativeAssetFaucet on a CGT devnet using the FaucetDeployer from L1.

## Architecture

```
L1                                          L2
┌─────────────┐                            ┌─────────────────────┐
│  MockSafe   │──delegatecall──►           │                     │
│  (Safe)     │            ┌───────────┐   │  NativeAssetFaucet  │
└─────────────┘            │  Faucet   │   │  (deployed via      │
                           │  Deployer │   │   CREATE2)          │
                           └─────┬─────┘   └─────────────────────┘
                                 │                    │
                                 │ depositTransaction │ authorized
                                 ▼                    ▼
                           ┌──────────┐      ┌───────────────────┐
                           │  Portal  │      │LiquidityController│
                           └──────────┘      └───────────────────┘
```

The LiquidityController owner on L2 is the **aliased address** of the MockSafe on L1:
- `L2_owner = L1_MockSafe + 0x1111000000000000000000000000000000001111`

## Prerequisites

- op-up running with CGT enabled
- The LiquidityController owner must be the aliased address of MockSafe

## Step 1: Deploy MockSafe on L1

```bash
cd /Users/corvus/Repos/op_repos/optimism/packages/contracts-bedrock

PRIVATE_KEY=0xd9fb56b9574ed61ab0478a607166eeb3a80b1b91ab1bf00f45932105d07b5e11

forge create src/L1/MockSafe.sol:MockSafe \
  --private-key $PRIVATE_KEY \
  --rpc-url http://127.0.0.1:8544 \
  --broadcast
```

Save the deployed address: `MOCK_SAFE=<deployed_address>`

## Step 2: Calculate the aliased address

```bash
MOCK_SAFE=0x8bcE16Ef26038f8EF673C3261a44230523014D4b  # use the address from step 1

python3 -c "
mock_safe = int('$MOCK_SAFE', 16)
offset = int('0x1111000000000000000000000000000000001111', 16)
aliased = (mock_safe + offset) % (2**160)
print(f'MockSafe aliased (L2): {hex(aliased)}')"
```

This address must match the LiquidityController owner on L2:
```bash
cast call 0x420000000000000000000000000000000000002a "owner()(address)" --rpc-url http://127.0.0.1:8545
```

**IMPORTANT**: If it doesn't match, update `op-up/main.go` with the new aliased address and restart op-up.

## Step 3: Get the Portal address

```bash
# From L2 CrossDomainMessenger -> L1 CrossDomainMessenger -> Portal
L1_MESSENGER=$(cast call 0x4200000000000000000000000000000000000007 "otherMessenger()(address)" --rpc-url http://127.0.0.1:8545)
echo "L1 Messenger: $L1_MESSENGER"

PORTAL=$(cast call $L1_MESSENGER "portal()(address)" --rpc-url http://127.0.0.1:8544)
echo "Portal: $PORTAL"

# Verify it has code
cast code $PORTAL --rpc-url http://127.0.0.1:8544 | head -c 100
```

## Step 4: Deploy FaucetDeployer on L1

```bash
PORTAL=<portal_from_step_3>
PRIVATE_KEY=0xd9fb56b9574ed61ab0478a607166eeb3a80b1b91ab1bf00f45932105d07b5e11

DEV_FEATURE__CUSTOM_GAS_TOKEN=true forge script scripts/DeployFaucetDeployer.s.sol \
  --rpc-url http://127.0.0.1:8544 \
  --broadcast
```

Save: `FAUCET_DEPLOYER=<deployed_address>`

## Step 5: Call deployAndAuthorize via MockSafe

```bash
MOCK_SAFE=<from_step_1>
FAUCET_DEPLOYER=<from_step_4>
FAUCET_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  # faucet owner
PERMISSIONLESS_AMOUNT=1000000000000000000  # 1 ETH per claim
GAS_LIMIT=500000

# Encode calldata
CALLDATA=$(cast calldata "deployAndAuthorize(address,uint256,uint64)" $FAUCET_OWNER $PERMISSIONLESS_AMOUNT $GAS_LIMIT)

# Execute via MockSafe delegatecall
cast send $MOCK_SAFE "executeDelegateCall(address,bytes)" $FAUCET_DEPLOYER $CALLDATA \
  --private-key 0xd9fb56b9574ed61ab0478a607166eeb3a80b1b91ab1bf00f45932105d07b5e11 \
  --rpc-url http://127.0.0.1:8544
```

## Step 6: Verify the Faucet on L2

The faucet address can be extracted from the second `TransactionDeposited` event log.
Look in the log data for the address after the `0x0c984832` selector (authorizeMinter).

```bash
FAUCET=<address_from_log>

# Verify it has code
cast code $FAUCET --rpc-url http://127.0.0.1:8545 | head -c 100

# Verify owner
cast call $FAUCET "owner()(address)" --rpc-url http://127.0.0.1:8545

# Verify it's authorized as minter
cast call 0x420000000000000000000000000000000000002a "minters(address)(bool)" $FAUCET --rpc-url http://127.0.0.1:8545
```

## Step 7: Test claim

```bash
FAUCET=<faucet_address>
RECIPIENT=0x1111111111111111111111111111111111111111

# Balance before
cast balance $RECIPIENT --rpc-url http://127.0.0.1:8545

# Claim (needs an account with funds on L2 to pay for gas)
cast send $FAUCET "claim(address)" $RECIPIENT \
  --private-key 0xd9fb56b9574ed61ab0478a607166eeb3a80b1b91ab1bf00f45932105d07b5e11 \
  --rpc-url http://127.0.0.1:8545

# Balance after (should have 1 ETH more)
cast balance $RECIPIENT --rpc-url http://127.0.0.1:8545
```

## Addresses from last successful test

| Component | Address |
|-----------|---------|
| MockSafe (L1) | `0x8bcE16Ef26038f8EF673C3261a44230523014D4b` |
| MockSafe Aliased (L2) | `0x9cDf16eF26038f8EF673C3261A44230523015e5C` |
| FaucetDeployer (L1) | `0xE948AfBDAa779Eafb4E608e9281e5e4e19ACDD1e` |
| Portal (L1) | `0x5C48c63A58A37c93578dD92E0515141050EC20D9` |
| NativeAssetFaucet (L2) | `0x0c3348692e1752d309f975f4423b21f44878a54c` |

## Notes

- The claim has a rate limit of once per block per recipient
- The `permissionlessAmount` defines how much can be claimed in permissionless mode
- The faucet owner can call `mint(address,uint256)` without limits
- Addresses change every time op-up is restarted (except predeploys)
