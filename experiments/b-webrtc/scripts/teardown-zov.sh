#!/usr/bin/env bash
# Remove olcrtc v0 from ZOV. Safe — only removes files this plan installed.
# Uses unlink/rmdir only (no rm -rf, per memory feedback_no_rm_rf.md).
set -euo pipefail
ssh ZenithOfVastness '
  sudo systemctl stop maskanya-olcrtc-bridge 2>/dev/null || true
  sudo systemctl disable maskanya-olcrtc-bridge 2>/dev/null || true
  sudo unlink /etc/systemd/system/maskanya-olcrtc-bridge.service 2>/dev/null || true
  sudo unlink /usr/local/bin/maskanya-olcrtc 2>/dev/null || true
  sudo unlink /etc/maskanya/olcrtc.env 2>/dev/null || true
  sudo rmdir /etc/maskanya 2>/dev/null || true
  sudo rmdir /var/lib/maskanya-olcrtc/data 2>/dev/null || true
  sudo rmdir /var/lib/maskanya-olcrtc 2>/dev/null || true
  sudo systemctl daemon-reload
  echo "olcrtc v0 removed from ZOV"
'
