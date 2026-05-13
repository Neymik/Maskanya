#!/usr/bin/env bash
# Deploy the jazz (SaluteJazz) fallback bridge to ZenithOfVastness.
# Parallel to the wbstream deploy — doesn't disturb the existing wbstream unit.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_LOCAL="experiments/b-webrtc/.env.olcrtc-jazz"
UNIT_LOCAL="experiments/b-webrtc/systemd/maskanya-olcrtc-jazz-bridge.service"

test -f "$ENV_LOCAL"  || { echo "FATAL: $ENV_LOCAL missing." >&2; exit 1; }
test -f "$UNIT_LOCAL" || { echo "FATAL: $UNIT_LOCAL missing." >&2; exit 1; }

# shellcheck disable=SC1091
source "$ENV_LOCAL"

echo "=== verifying passwordless sudo on ZOV ==="
ssh ZenithOfVastness 'sudo -n true' 2>/dev/null || { echo "FATAL: passwordless sudo required." >&2; exit 1; }

# Binary already on ZOV from wbstream deploy (same binary; carrier is a runtime flag).
echo "=== using existing /usr/local/bin/maskanya-olcrtc on ZOV ==="
ssh ZenithOfVastness 'test -x /usr/local/bin/maskanya-olcrtc && echo "binary present" || (echo "FATAL: deploy wbstream first via deploy-zov.sh" >&2; exit 1)'

echo "=== uploading jazz systemd unit ==="
scp -q "$UNIT_LOCAL" ZenithOfVastness:/tmp/maskanya-olcrtc-jazz-bridge.service

echo "=== writing /etc/maskanya/olcrtc-jazz.env on ZOV ==="
ssh ZenithOfVastness "sudo install -d -m 0750 /etc/maskanya"
ssh ZenithOfVastness "sudo tee /etc/maskanya/olcrtc-jazz.env >/dev/null" <<ENVEOF
OLCRTC_KEY=$OLCRTC_KEY
OLCRTC_ROOM_ID=$OLCRTC_ROOM_ID
OLCRTC_CLIENT_ID=$OLCRTC_CLIENT_ID
OLCRTC_CARRIER=$OLCRTC_CARRIER
OLCRTC_TRANSPORT=$OLCRTC_TRANSPORT
ENVEOF
ssh ZenithOfVastness "sudo chmod 0600 /etc/maskanya/olcrtc-jazz.env && sudo chown root:root /etc/maskanya/olcrtc-jazz.env"

echo "=== installing jazz systemd unit ==="
ssh ZenithOfVastness "sudo install -m 0644 /tmp/maskanya-olcrtc-jazz-bridge.service /etc/systemd/system/maskanya-olcrtc-jazz-bridge.service && unlink /tmp/maskanya-olcrtc-jazz-bridge.service"

echo "=== daemon-reload ==="
ssh ZenithOfVastness 'sudo systemctl daemon-reload'

echo
echo "DEPLOYED. Jazz unit loaded but NOT started. Start with:"
echo "  ssh ZenithOfVastness 'sudo systemctl start maskanya-olcrtc-jazz-bridge'"
