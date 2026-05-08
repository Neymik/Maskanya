#!/usr/bin/env bash
# Remove xray-poc from MSK. Single-hop variant — no ZOV-side work to undo.
set -euo pipefail
ALIAS=MaskanyaHopMsk

echo "→ ${ALIAS}: stopping + removing xray-poc"
ssh "$ALIAS" "systemctl disable --now xray-poc.service 2>/dev/null || true"
ssh "$ALIAS" "rm -f /etc/systemd/system/xray-poc.service && systemctl daemon-reload"
ssh "$ALIAS" "rm -rf /opt/xray-poc"

echo "→ ${ALIAS}: removing iptables rule for :443"
ssh "$ALIAS" "iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true"

echo "✓ torn down."
