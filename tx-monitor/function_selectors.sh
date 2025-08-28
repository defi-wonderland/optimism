#!/usr/bin/env bash
set -euo pipefail

# Script to extract function selectors from contract ABI files
# Usage: ./function_selectors.sh <abi_file_path>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <abi_file_path>"
    echo "Example: $0 ../packages/contracts-bedrock/snapshots/abi/LiquidityController.json"
    exit 1
fi

ABI_FILE="$1"

if [ ! -f "$ABI_FILE" ]; then
    echo "Error: File $ABI_FILE not found"
    exit 1
fi

echo "Function selectors for $(basename "$ABI_FILE" .json):"
echo "=================================================="

# Extract functions from ABI and get their selectors using cast
jq -r '.[] | select(.type == "function") | .name + "(" + ([.inputs[].type] | join(",")) + ")"' "$ABI_FILE" | while read -r func_signature; do
    selector=$(cast sig "$func_signature" 2>/dev/null || echo "Error calculating selector")
    printf "%-50s %s\n" "$func_signature" "$selector"
done