#!/usr/bin/env bash
# Deploy olcrtc v0 to ZenithOfVastness via SSH (no Ansible — manual, fast).
# Idempotent: re-runnable; updates binary + env + unit in place.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_LOCAL="experiments/b-webrtc/.env.olcrtc-v0"
BIN_LOCAL="experiments/b-webrtc/build/maskanya-olcrtc-linux-amd64"
UNIT_LOCAL="experiments/b-webrtc/systemd/maskanya-olcrtc-bridge.service"

test -f "$ENV_LOCAL"  || { echo "FATAL: $ENV_LOCAL missing — run Task 4." >&2; exit 1; }
test -f "$BIN_LOCAL"  || { echo "FATAL: $BIN_LOCAL missing — run Task 3." >&2; exit 1; }
test -f "$UNIT_LOCAL" || { echo "FATAL: $UNIT_LOCAL missing." >&2; exit 1; }

# shellcheck disable=SC1091
source "$ENV_LOCAL"

echo "=== verifying passwordless sudo on ZOV ==="
ssh ZenithOfVastness 'sudo -n true' 2>/dev/null || {
  echo "FATAL: passwordless sudo not available on ZOV. Configure /etc/sudoers.d/ or run with ssh -t." >&2
  exit 1
}

echo "=== scp binary ==="
scp -q "$BIN_LOCAL" ZenithOfVastness:/tmp/maskanya-olcrtc

echo "=== scp systemd unit ==="
scp -q "$UNIT_LOCAL" ZenithOfVastness:/tmp/maskanya-olcrtc-bridge.service

echo "=== writing /etc/maskanya/olcrtc.env on ZOV ==="
ssh ZenithOfVastness "sudo install -d -m 0750 /etc/maskanya"
ssh ZenithOfVastness "sudo tee /etc/maskanya/olcrtc.env >/dev/null" <<ENVEOF
OLCRTC_KEY=$OLCRTC_KEY
OLCRTC_ROOM_ID=$OLCRTC_ROOM_ID
OLCRTC_CLIENT_ID=$OLCRTC_CLIENT_ID
OLCRTC_CARRIER=$OLCRTC_CARRIER
OLCRTC_TRANSPORT=$OLCRTC_TRANSPORT
ENVEOF
ssh ZenithOfVastness "sudo chmod 0600 /etc/maskanya/olcrtc.env && sudo chown root:root /etc/maskanya/olcrtc.env"

echo "=== installing binary + unit ==="
ssh ZenithOfVastness "sudo install -m 0755 /tmp/maskanya-olcrtc /usr/local/bin/maskanya-olcrtc"
ssh ZenithOfVastness "sudo install -m 0644 /tmp/maskanya-olcrtc-bridge.service /etc/systemd/system/maskanya-olcrtc-bridge.service"

echo "=== removing scp staging files ==="
# install (above) COPIED; /tmp leftovers are not secrets but unneeded.
ssh ZenithOfVastness "unlink /tmp/maskanya-olcrtc 2>/dev/null || true; unlink /tmp/maskanya-olcrtc-bridge.service 2>/dev/null || true"

echo "=== systemd daemon-reload ==="
ssh ZenithOfVastness "sudo systemctl daemon-reload"

echo
echo "DEPLOYED. Service is loaded but NOT enabled (manual-start, v0)."
echo "Next: ssh ZenithOfVastness 'sudo systemctl start maskanya-olcrtc-bridge'"
