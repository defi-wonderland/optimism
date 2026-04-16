#!/usr/bin/env bash
# Deposit ETH from L1 to L2 via the OptimismPortal.
# Usage: deposit-l1-to-l2.sh <amount_eth>
# Requires: OP_PG_L1_RPC, OP_PG_DEV_PRIVKEY, OP_PG_PORTAL_ADDR
set -euo pipefail

AMOUNT="${1:?usage: deposit-l1-to-l2.sh <amount_eth>}"
L1_RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
PORTAL="${OP_PG_PORTAL_ADDR:?set OP_PG_PORTAL_ADDR to the OptimismPortal proxy address}"

echo "Depositing ${AMOUNT} ETH via OptimismPortal at ${PORTAL}..."
cast send --rpc-url "$L1_RPC" --private-key "$OP_PG_DEV_PRIVKEY" "$PORTAL" --value "${AMOUNT}ether" "depositTransaction(address,uint256,uint64,bool,bytes)" "$OP_PG_DEV_ADDR" "${AMOUNT}000000000000000000" 100000 false 0x

echo "Deposit TX sent. It may take a few L1 blocks to appear on L2."
