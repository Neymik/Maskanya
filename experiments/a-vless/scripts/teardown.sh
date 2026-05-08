#!/usr/bin/env bash
# Remove xray-poc from both hosts. Leaves /opt/xray-poc/ deleted and removes
# the additive iptables ACCEPT rules. Production xray-maskanya is untouched.
set -euo pipefail

teardown_host() {
    local alias="$1" listen_port="$2" allow_from="$3"
    echo "→ ${alias}: stopping + removing xray-poc"
    ssh "$alias" "systemctl disable --now xray-poc.service 2>/dev/null || true"
    ssh "$alias" "rm -f /etc/systemd/system/xray-poc.service && systemctl daemon-reload"
    ssh "$alias" "rm -rf /opt/xray-poc"
    echo "→ ${alias}: removing iptables rule"
    ssh "$alias" "iptables -D INPUT -p tcp --dport ${listen_port} -s ${allow_from} -j ACCEPT 2>/dev/null || true"
}

teardown_host ZenithOfVastness 2053 82.146.35.191/32
teardown_host MaskanyaHopMsk    443  0.0.0.0/0

echo "✓ torn down."
