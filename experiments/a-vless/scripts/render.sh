#!/usr/bin/env bash
# Substitute env vars into the JSON template → rendered config.
# Run after sourcing the output of keygen.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

required=(MSK_REALITY_PRIVATE_KEY MSK_SHORT_ID USER_UUID)
for v in "${required[@]}"; do
    if [ -z "${!v:-}" ]; then
        echo "ERROR: env var $v is not set. source .env.poc-a first." >&2
        exit 1
    fi
done

vars='$MSK_REALITY_PRIVATE_KEY $MSK_SHORT_ID $USER_UUID'
envsubst "$vars" < configs/msk.json.tmpl > configs/msk-rendered.json
echo "Rendered: configs/msk-rendered.json"
