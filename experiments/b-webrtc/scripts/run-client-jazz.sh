#!/usr/bin/env bash
# Run olcrtc client (cnc mode) against the JAZZ (SaluteJazz) carrier.
# Mirror of run-client.sh but uses .env.olcrtc-jazz.
# SOCKS5 on 127.0.0.1:1080.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_LOCAL="experiments/b-webrtc/.env.olcrtc-jazz"
test -f "$ENV_LOCAL" || { echo "FATAL: $ENV_LOCAL missing — generate via -mode gen first." >&2; exit 1; }

# shellcheck disable=SC1091
source "$ENV_LOCAL"

HOST_OS=$(go env GOOS)
HOST_ARCH=$(go env GOARCH)
BIN="experiments/b-webrtc/build/maskanya-olcrtc-${HOST_OS}-${HOST_ARCH}"
DATA="experiments/b-webrtc/build/data-jazz"

test -x "$BIN" || { echo "FATAL: $BIN missing — run scripts/build.sh first." >&2; exit 1; }
mkdir -p "$DATA"

echo "Starting olcrtc client (cnc) → jazz carrier → SOCKS5 on 127.0.0.1:1080"
echo "Room: $OLCRTC_ROOM_ID"
echo "Ctrl-C to stop."
echo

exec "$BIN" \
  -mode cnc \
  -carrier "$OLCRTC_CARRIER" \
  -transport "$OLCRTC_TRANSPORT" \
  -id "$OLCRTC_ROOM_ID" \
  -client-id "$OLCRTC_CLIENT_ID" \
  -key "$OLCRTC_KEY" \
  -link direct \
  -dns 1.1.1.1:53 \
  -data "$DATA" \
  -socks-host 127.0.0.1 \
  -socks-port 1080 \
  -vp8-fps 25 \
  -vp8-batch 1
