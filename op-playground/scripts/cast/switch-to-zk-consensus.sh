#!/usr/bin/env bash
# Flip the L2 to finalize via ZK_DISPUTE_GAME (gameType=10). Run upgrade-to-zk first.
# Requires: OP_PG_L1_RPC, OP_PG_PORTAL, OP_PG_GUARDIAN_PRIVKEY, OP_PG_DGF.
set -euo pipefail

RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
: "${OP_PG_PORTAL:?missing OP_PG_PORTAL}"
: "${OP_PG_GUARDIAN_PRIVKEY:?missing OP_PG_GUARDIAN_PRIVKEY}"
: "${OP_PG_DGF:?missing OP_PG_DGF}"

# Refuse if no impl is registered at gameType=10.
ZK_IMPL=$(cast call --rpc-url "$RPC" "$OP_PG_DGF" 'gameImpls(uint32)(address)' 10)
if [ "$ZK_IMPL" = "0x0000000000000000000000000000000000000000" ]; then
    echo "ERROR: no implementation at gameType=10. Run 'upgrade-to-zk' first." >&2
    exit 1
fi
echo "Found ZK_DISPUTE_GAME impl: $ZK_IMPL"

CONTRACTS="${OP_PG_CONTRACTS_DIR:-$(pwd)/../packages/contracts-bedrock}"
cd "$CONTRACTS"

OP_PG_TARGET_GAME_TYPE=10 forge script scripts/playground/SetRespectedGameType.s.sol:SetRespectedGameType \
    --rpc-url "$RPC" \
    --broadcast \
    --slow \
    --skip-simulation
