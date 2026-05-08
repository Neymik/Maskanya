#!/usr/bin/env bash
# Substitute env vars into JSON templates → rendered configs.
# Run after sourcing the output of keygen.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

required=(ZOV_REALITY_PRIVATE_KEY ZOV_REALITY_PUBLIC_KEY ZOV_SHORT_ID
          MSK_REALITY_PRIVATE_KEY MSK_SHORT_ID
          CHAIN_UUID USER_UUID)
for v in "${required[@]}"; do
    if [ -z "${!v:-}" ]; then
        echo "ERROR: env var $v is not set. source .env.poc-a first." >&2
        exit 1
    fi
done

# envsubst respects only listed vars (avoid clobbering anything else)
vars='$ZOV_REALITY_PRIVATE_KEY $ZOV_REALITY_PUBLIC_KEY $ZOV_SHORT_ID '
vars+='$MSK_REALITY_PRIVATE_KEY $MSK_SHORT_ID '
vars+='$CHAIN_UUID $USER_UUID'

envsubst "$vars" < configs/zov.json.tmpl > configs/zov-rendered.json
envsubst "$vars" < configs/msk.json.tmpl > configs/msk-rendered.json

echo "Rendered:"
echo "  configs/zov-rendered.json"
echo "  configs/msk-rendered.json"
