#!/usr/bin/env bash
# Watch new blocks on L2 (or L1 with --l1 flag)
set -euo pipefail

if [[ "${1:-}" == "--l1" ]]; then
  RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
  LABEL="L1"
else
  RPC="${OP_PG_L2_RPC:-http://localhost:8545}"
  LABEL="L2"
fi

LAST=0
while true; do
  NUM=$(cast block-number --rpc-url "$RPC" 2>/dev/null || echo "$LAST")
  if [[ "$NUM" != "$LAST" ]]; then
    HASH=$(cast block "$NUM" --rpc-url "$RPC" --json 2>/dev/null | jq -r '.hash // "unknown"')
    echo "[$LABEL] Block #${NUM} ${HASH}"
    LAST="$NUM"
  fi
  sleep 1
done
