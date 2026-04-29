#!/usr/bin/env bash
# Inspect the L2 dispute system on L1: factory, anchor registry, registered game types, recent games.
# Requires: OP_PG_L1_RPC, OP_PG_DGF, OP_PG_PORTAL.
set -euo pipefail

RPC="${OP_PG_L1_RPC:-http://localhost:8547}"
DGF="${OP_PG_DGF:?missing OP_PG_DGF}"
PORTAL="${OP_PG_PORTAL:?missing OP_PG_PORTAL}"

call() { cast call --rpc-url "$RPC" "$@"; }

echo "=== Portal ($PORTAL) ==="
echo "  version             $(call "$PORTAL" 'version()(string)')"
echo "  respectedGameType   $(call "$PORTAL" 'respectedGameType()(uint32)')"
ASR=$(call "$PORTAL" 'anchorStateRegistry()(address)')
echo "  anchorStateRegistry $ASR"

echo
echo "=== DisputeGameFactory ($DGF) ==="
echo "  version    $(call "$DGF" 'version()(string)')"
echo "  owner      $(call "$DGF" 'owner()(address)')"
COUNT=$(call "$DGF" 'gameCount()(uint256)')
echo "  gameCount  $COUNT"

echo
echo "=== Game type implementations ==="
declare -A NAME=(
  [0]=CANNON [1]=PERMISSIONED_CANNON [2]=ASTERISC [3]=ASTERISC_KONA
  [4]=SUPER_CANNON [5]=SUPER_PERMISSIONED_CANNON [6]=OP_SUCCINCT
  [8]=CANNON_KONA [9]=SUPER_CANNON_KONA [10]=ZK_DISPUTE_GAME
)
printf "  %-3s %-30s %-44s %s\n" "gt" "name" "impl" "initBond"
for t in 0 1 2 3 4 5 6 8 9 10; do
  IMPL=$(call "$DGF" 'gameImpls(uint32)(address)' "$t")
  BOND=$(call "$DGF" 'initBonds(uint32)(uint256)' "$t")
  printf "  %-3s %-30s %-44s %s\n" "$t" "${NAME[$t]:-?}" "$IMPL" "$BOND"
done

echo
if [ "$COUNT" -gt 0 ] 2>/dev/null; then
  START=$((COUNT > 5 ? COUNT - 5 : 0))
  echo "=== Recent games (last $((COUNT - START))) ==="
  for ((i=COUNT-1; i>=START; i--)); do
    OUT=$(call "$DGF" 'gameAtIndex(uint256)(uint32,uint64,address)' "$i")
    GT=$(echo "$OUT" | sed -n '1p')
    TS=$(echo "$OUT" | sed -n '2p')
    PROXY=$(echo "$OUT" | sed -n '3p')
    printf "  #%-4d type=%-3s ts=%-12s proxy=%s\n" "$i" "$GT" "$TS" "$PROXY"
  done
fi
