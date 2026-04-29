#!/usr/bin/env bash
# Revert the L2 to finalize via PERMISSIONED_CANNON (gameType=1).
# Requires: OP_PG_L1_RPC, OP_PG_PORTAL, OP_PG_GUARDIAN_PRIVKEY.
set -euo pipefail

RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
: "${OP_PG_PORTAL:?missing OP_PG_PORTAL}"
: "${OP_PG_GUARDIAN_PRIVKEY:?missing OP_PG_GUARDIAN_PRIVKEY}"

CONTRACTS="${OP_PG_CONTRACTS_DIR:-$(pwd)/../packages/contracts-bedrock}"
cd "$CONTRACTS"

OP_PG_TARGET_GAME_TYPE=1 forge script scripts/playground/SetRespectedGameType.s.sol:SetRespectedGameType \
    --rpc-url "$RPC" \
    --broadcast \
    --slow \
    --skip-simulation
