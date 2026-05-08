#!/usr/bin/env bash
# Emit the client subscription URI for the PoC. Reads env vars from keygen.sh output.
set -euo pipefail

required=(USER_UUID MSK_REALITY_PUBLIC_KEY MSK_SHORT_ID)
for v in "${required[@]}"; do
    if [ -z "${!v:-}" ]; then
        echo "ERROR: env var $v is not set. source .env.poc-a first." >&2
        exit 1
    fi
done

# URL-encode '/'
PATH_ENCODED="%2Fpoc"

cat <<EOF
vless://${USER_UUID}@82.146.35.191:443?type=xhttp&mode=stream-one&path=${PATH_ENCODED}&security=reality&pbk=${MSK_REALITY_PUBLIC_KEY}&sid=${MSK_SHORT_ID}&sni=storage.yandex.net&fp=chrome&flow=xtls-rprx-vision#Maskanya-PoC-A
EOF
