#!/usr/bin/env bash
# Read sync status from the op-node RPC
set -euo pipefail

ROLLUP_RPC="${OP_PG_ROLLUP_RPC:-http://localhost:9545}"

echo "Querying sync status from $ROLLUP_RPC..."
cast rpc --rpc-url "$ROLLUP_RPC" optimism_syncStatus | jq .
