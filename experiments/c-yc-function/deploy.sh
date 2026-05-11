#!/usr/bin/env bash
# Deploy the fetch-relay function to Yandex Cloud.
# Idempotent: re-running creates a new version of the same function.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Copy .env.example to .env and fill in." >&2
    exit 1
fi
# shellcheck disable=SC1091
source .env

for v in FOLDER_ID SERVICE_ACCOUNT_ID FUNCTION_NAME BEARER_TOKEN; do
    if [ -z "${!v:-}" ]; then
        echo "ERROR: $v is empty in .env" >&2
        exit 1
    fi
done

# Create function (idempotent — yc returns the existing one if it exists)
echo "→ ensuring function '${FUNCTION_NAME}' exists"
yc serverless function get --name "$FUNCTION_NAME" --folder-id "$FOLDER_ID" >/dev/null 2>&1 \
    || yc serverless function create --name "$FUNCTION_NAME" --folder-id "$FOLDER_ID" --description "PoC"

# Bundle source
echo "→ bundling source"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp index.js package.json "$TMP/"
( cd "$TMP" && zip -q function.zip index.js package.json )

# Create new version
echo "→ creating new version"
yc serverless function version create \
    --function-name "$FUNCTION_NAME" \
    --folder-id "$FOLDER_ID" \
    --runtime nodejs22 \
    --entrypoint index.handler \
    --memory 256m \
    --execution-timeout 60s \
    --service-account-id "$SERVICE_ACCOUNT_ID" \
    --source-path "$TMP/function.zip" \
    --environment "BEARER_TOKEN=$BEARER_TOKEN"

# Make function publicly invokable (no IAM check — gated only by our bearer token).
# Without this the function URL returns 401 unauthorized at the YC layer before
# our handler runs.
echo "→ making function public"
yc serverless function allow-unauthenticated-invoke \
    --name "$FUNCTION_NAME" \
    --folder-id "$FOLDER_ID" \
    >/dev/null 2>&1 || true

# Print the URL
URL=$(yc serverless function get --name "$FUNCTION_NAME" --folder-id "$FOLDER_ID" --format json | jq -r '.http_invoke_url')
echo
echo "✓ deployed."
echo "  URL: $URL"
echo
echo "  Test:"
echo "    curl -X POST '$URL' \\"
echo "      -H 'X-Maskanya-Token: $BEARER_TOKEN' \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"url\":\"https://ifconfig.me\"}'"
echo
echo "  NOTE: auth header is X-Maskanya-Token, NOT Authorization."
echo "  YC API gateway intercepts 'Authorization: Bearer ...' as IAM token"
echo "  and 403s before our handler runs."
