#!/usr/bin/env bash
# Generate Reality keypairs (one per host) + UUIDs for the PoC.
# Pulls a temporary xray binary on ZOV (already exists at /usr/local/bin/xray-maskanya
# from production), uses it for `xray x25519`. Falls back to local xray if available.
#
# Output: env-var assignments. Capture into a file:
#   ./scripts/keygen.sh > .env.poc-a
#   source .env.poc-a
set -euo pipefail

XRAY_BIN_REMOTE=/usr/local/bin/xray-maskanya

gen_keypair() {
    # Tries to use existing xray on ZOV; if missing, prints a manual fallback.
    if ssh ZenithOfVastness "test -x $XRAY_BIN_REMOTE" 2>/dev/null; then
        ssh ZenithOfVastness "$XRAY_BIN_REMOTE x25519"
    elif command -v xray >/dev/null 2>&1; then
        xray x25519
    else
        echo "ERROR: no xray binary on ZOV at $XRAY_BIN_REMOTE and no local xray." >&2
        echo "Install xray locally (https://github.com/XTLS/Xray-core/releases) or" >&2
        echo "deploy ZOV's production xray-maskanya first, then re-run." >&2
        exit 1
    fi
}

extract_field() {
    # xray x25519 prints two lines:
    #   Private key: ...
    #   Public key: ...
    grep -i "^${1}" | awk -F': *' '{print $2}'
}

echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — keep secret" >&2

ZOV_KP=$(gen_keypair)
ZOV_PRIV=$(printf '%s\n' "$ZOV_KP" | extract_field "Private key")
ZOV_PUB=$(printf '%s\n' "$ZOV_KP" | extract_field "Public key")

MSK_KP=$(gen_keypair)
MSK_PRIV=$(printf '%s\n' "$MSK_KP" | extract_field "Private key")
MSK_PUB=$(printf '%s\n' "$MSK_KP" | extract_field "Public key")

ZOV_SID=$(openssl rand -hex 4)
MSK_SID=$(openssl rand -hex 4)

CHAIN_UUID=$(uuidgen | tr 'A-Z' 'a-z')
USER_UUID=$(uuidgen | tr 'A-Z' 'a-z')

cat <<EOF
export ZOV_REALITY_PRIVATE_KEY='$ZOV_PRIV'
export ZOV_REALITY_PUBLIC_KEY='$ZOV_PUB'
export ZOV_SHORT_ID='$ZOV_SID'
export MSK_REALITY_PRIVATE_KEY='$MSK_PRIV'
export MSK_REALITY_PUBLIC_KEY='$MSK_PUB'
export MSK_SHORT_ID='$MSK_SID'
export CHAIN_UUID='$CHAIN_UUID'
export USER_UUID='$USER_UUID'
EOF
