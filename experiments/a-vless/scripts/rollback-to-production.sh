#!/usr/bin/env bash
# Restore production xray-maskanya config from the latest pre-PoC backup.
# Use this if VAL-01 fails (or finishes) and you want production back.
set -euo pipefail
ALIAS=MaskanyaHopMsk

echo "→ ${ALIAS}: locating most recent backup"
BACKUP=$(ssh "$ALIAS" 'sudo bash -c "ls -1t /etc/xray/config.json.pre-poc.bak.* 2>/dev/null | head -1"')

if [ -z "$BACKUP" ]; then
    echo "ERROR: no /etc/xray/config.json.pre-poc.bak.* file found on ${ALIAS}." >&2
    echo "Backup was either never made or already cleaned up." >&2
    exit 1
fi

echo "  found: $BACKUP"
echo "→ ${ALIAS}: restoring backup → /etc/xray/config.json"
ssh "$ALIAS" "sudo cp '$BACKUP' /etc/xray/config.json && \
              sudo chown xray-maskanya:xray-maskanya /etc/xray/config.json && \
              sudo chmod 0640 /etc/xray/config.json"

echo "→ ${ALIAS}: restarting xray-maskanya"
ssh "$ALIAS" 'sudo systemctl restart xray-maskanya && sleep 2 && sudo systemctl --no-pager --lines=3 status xray-maskanya | head -5'

echo
echo "✓ rolled back. The PoC backup file is left in place at: $BACKUP"
echo "  Delete it manually after confirming production is healthy:"
echo "    ssh ${ALIAS} sudo rm '$BACKUP'"
