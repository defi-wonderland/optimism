#!/usr/bin/env bash
# Transfer ETH on L2. Usage: transfer-l2.sh <to_address> <amount_eth>
# Requires: OP_PG_L2_RPC, OP_PG_DEV_PRIVKEY environment variables
set -euo pipefail

TO="${1:?usage: transfer-l2.sh <to_address> <amount_eth>}"
AMOUNT="${2:?usage: transfer-l2.sh <to_address> <amount_eth>}"
RPC="${OP_PG_L2_RPC:-http://localhost:8545}"

cast send --rpc-url "$RPC" --private-key "$OP_PG_DEV_PRIVKEY" "$TO" --value "${AMOUNT}ether"
echo "Sent ${AMOUNT} ETH to ${TO} on L2"
