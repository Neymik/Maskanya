#!/usr/bin/env bash
# Deploy xray-poc to MSK (port 443) — single-hop variant.
# Idempotent: re-run after editing rendered config to update.
#
# Side-effects on MSK:
#   /opt/xray-poc/xray            (binary)
#   /opt/xray-poc/config.json     (rendered config)
#   /etc/systemd/system/xray-poc.service
#   one iptables ACCEPT rule for :443/tcp
#
# Does NOT touch ZOV at all in this single-hop variant. ZOV-side work moves
# to Phase 1 (nginx SNI demuxer + xray Reality on internal :8443).
set -euo pipefail
cd "$(dirname "$0")/.."

XRAY_VERSION="${XRAY_VERSION:-25.5.5}"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"

CACHE_DIR="$HOME/.cache/maskanya-poc"
mkdir -p "$CACHE_DIR"
ZIP="$CACHE_DIR/xray-${XRAY_VERSION}.zip"
BIN="$CACHE_DIR/xray-${XRAY_VERSION}"

if [ ! -x "$BIN" ]; then
    echo "→ downloading xray v${XRAY_VERSION}"
    curl -fsSL -o "$ZIP" "$XRAY_URL"
    unzip -p "$ZIP" xray > "$BIN"
    chmod +x "$BIN"
fi

ALIAS=MaskanyaHopMsk

# Pre-flight: confirm :443 is free on MSK before we try to bind.
echo "→ ${ALIAS}: checking :443 is free"
if ssh "$ALIAS" "ss -tlnp | grep -q ':443 '"; then
    echo "ERROR: ${ALIAS}:443 is already bound. Kill the listener before deploying:" >&2
    ssh "$ALIAS" "ss -tlnp | grep ':443 '" >&2
    exit 1
fi

echo "→ ${ALIAS}: pushing binary + config"
ssh "$ALIAS" "mkdir -p /opt/xray-poc"
scp -q "$BIN" "${ALIAS}:/opt/xray-poc/xray"
scp -q configs/msk-rendered.json "${ALIAS}:/opt/xray-poc/config.json"

echo "→ ${ALIAS}: writing systemd unit"
ssh "$ALIAS" 'cat > /etc/systemd/system/xray-poc.service' <<'UNIT'
[Unit]
Description=Maskanya xray-poc (single-hop PoC)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/xray-poc/xray run -config /opt/xray-poc/config.json
# CAP_NET_BIND_SERVICE so we can bind :443 without running as root
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/log

[Install]
WantedBy=multi-user.target
UNIT

echo "→ ${ALIAS}: opening :443 to the world (PoC inbound)"
ssh "$ALIAS" "iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null \
              || iptables -I INPUT -p tcp --dport 443 -j ACCEPT"

echo "→ ${ALIAS}: starting xray-poc"
ssh "$ALIAS" "systemctl daemon-reload && systemctl enable --now xray-poc.service && systemctl restart xray-poc.service"
ssh "$ALIAS" "systemctl --no-pager --lines=5 status xray-poc.service" || true

echo
echo "✓ deployed. Run scripts/gen-client-uri.sh to get the v2rayN URI."
echo "  Logs: ssh ${ALIAS} journalctl -u xray-poc -f"
