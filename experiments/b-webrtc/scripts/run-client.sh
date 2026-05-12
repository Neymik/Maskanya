#!/usr/bin/env bash
# Run olcrtc client (cnc mode) on the operator's local workstation.
# Exposes SOCKS5 on 127.0.0.1:1080.
# Run from anywhere; resolves repo root via git.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_LOCAL="experiments/b-webrtc/.env.olcrtc-v0"
test -f "$ENV_LOCAL" || { echo "FATAL: $ENV_LOCAL missing — run Task 4 first." >&2; exit 1; }

# shellcheck disable=SC1091
source "$ENV_LOCAL"

HOST_OS=$(go env GOOS)
HOST_ARCH=$(go env GOARCH)
BIN="experiments/b-webrtc/build/maskanya-olcrtc-${HOST_OS}-${HOST_ARCH}"
DATA="experiments/b-webrtc/build/data"

test -x "$BIN" || { echo "FATAL: $BIN missing — run Task 3 first." >&2; exit 1; }
mkdir -p "$DATA"

echo "Starting olcrtc client (cnc) → SOCKS5 on 127.0.0.1:1080"
echo "Carrier:   $OLCRTC_CARRIER"
echo "Transport: $OLCRTC_TRANSPORT"
echo "Room ID:   $OLCRTC_ROOM_ID"
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
  -socks-port 1080
