#!/usr/bin/env bash
# Generate a Reality keypair + UUID + short ID for the single-hop PoC.
# Tries to use existing xray on ZOV (production xray-maskanya), then falls back
# to local xray. Output is env-var assignments — capture into a file:
#
#   ./scripts/keygen.sh > .env.poc-a
#   source .env.poc-a
set -euo pipefail

XRAY_BIN_REMOTE=/usr/local/bin/xray-maskanya

gen_keypair() {
    if ssh ZenithOfVastness "test -x $XRAY_BIN_REMOTE" 2>/dev/null; then
        ssh ZenithOfVastness "$XRAY_BIN_REMOTE x25519"
    elif command -v xray >/dev/null 2>&1; then
        xray x25519
    else
        echo "ERROR: no xray binary on ZOV at $XRAY_BIN_REMOTE and no local xray." >&2
        echo "Either deploy ZOV's production xray-maskanya first, or install xray locally" >&2
        echo "(https://github.com/XTLS/Xray-core/releases) and re-run." >&2
        exit 1
    fi
}

extract_field() {
    grep -i "^${1}" | awk -F': *' '{print $2}'
}

KP=$(gen_keypair)
# Xray 25.x renamed the labels: "Private key:"/"Public key:" → "PrivateKey:"/"Password:".
# Older xray (<25) still uses the spaced form. Try both.
PRIV=$(printf '%s\n' "$KP" | extract_field "PrivateKey")
[ -z "$PRIV" ] && PRIV=$(printf '%s\n' "$KP" | extract_field "Private key")
PUB=$(printf '%s\n' "$KP" | extract_field "Password")
[ -z "$PUB" ] && PUB=$(printf '%s\n' "$KP" | extract_field "Public key")
SID=$(openssl rand -hex 4)
UUID=$(uuidgen | tr 'A-Z' 'a-z')

cat <<EOF
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — keep secret
export MSK_REALITY_PRIVATE_KEY='$PRIV'
export MSK_REALITY_PUBLIC_KEY='$PUB'
export MSK_SHORT_ID='$SID'
export USER_UUID='$UUID'
EOF
