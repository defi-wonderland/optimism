#!/usr/bin/env bash
# Register ZKDisputeGame (with ZKMockVerifier) at gameType=10 on the playground L1.
# Reuses the existing AnchorStateRegistry + DelayedWETH from the running deployment.
# Requires: OP_PG_L1_RPC, OP_PG_DGF, OP_PG_PORTAL, OP_PG_OWNER_PRIVKEY, OP_PG_DEV_PRIVKEY.
set -euo pipefail

RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
: "${OP_PG_DGF:?missing OP_PG_DGF}"
: "${OP_PG_PORTAL:?missing OP_PG_PORTAL}"
: "${OP_PG_OWNER_PRIVKEY:?missing OP_PG_OWNER_PRIVKEY}"
: "${OP_PG_DEV_PRIVKEY:?missing OP_PG_DEV_PRIVKEY}"

CONTRACTS="${OP_PG_CONTRACTS_DIR:-$(pwd)/../packages/contracts-bedrock}"
if [ ! -d "$CONTRACTS" ]; then
    echo "contracts-bedrock not found at $CONTRACTS — set OP_PG_CONTRACTS_DIR" >&2
    exit 1
fi

cd "$CONTRACTS"

echo ">>> Running forge script UpgradeToZK against $RPC"
forge script scripts/playground/UpgradeToZK.s.sol:UpgradeToZK \
    --rpc-url "$RPC" \
    --broadcast \
    --slow \
    --skip-simulation
echo
echo ">>> Verifying gameType=10 is registered"
cast call --rpc-url "$RPC" "$OP_PG_DGF" 'gameImpls(uint32)(address)' 10
echo
echo "Refresh the dashboard — the Consensus panel should now list ZK_DISPUTE_GAME."
