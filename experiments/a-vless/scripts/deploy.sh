#!/usr/bin/env bash
# Deploy xray-poc to ZOV (port 2053) and MSK (port 443).
# Idempotent: re-run after editing rendered configs to update.
#
# Side-effects on each host:
#   /opt/xray-poc/xray            (binary)
#   /opt/xray-poc/config.json     (rendered config)
#   /etc/systemd/system/xray-poc.service
#   one iptables ACCEPT rule
#
# Does NOT touch the production xray-maskanya service or its files.
set -euo pipefail
cd "$(dirname "$0")/.."

XRAY_VERSION="${XRAY_VERSION:-25.5.5}"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"

# --- Local: download xray once into a cache --------------------------------
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

# --- Remote: per-host deploy -----------------------------------------------
deploy_host() {
    local alias="$1" config_path="$2" listen_port="$3" allow_from="$4"

    echo "→ ${alias}: pushing binary + config"
    ssh "$alias" "mkdir -p /opt/xray-poc"
    scp -q "$BIN" "${alias}:/opt/xray-poc/xray"
    scp -q "$config_path" "${alias}:/opt/xray-poc/config.json"

    echo "→ ${alias}: writing systemd unit"
    ssh "$alias" 'cat > /etc/systemd/system/xray-poc.service' <<'UNIT'
[Unit]
Description=Maskanya xray-poc (PoC, isolated from production xray-maskanya)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/xray-poc/xray run -config /opt/xray-poc/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/log

[Install]
WantedBy=multi-user.target
UNIT

    echo "→ ${alias}: opening :${listen_port} for ${allow_from}"
    # additive iptables rule; idempotent via -C check first
    ssh "$alias" "iptables -C INPUT -p tcp --dport ${listen_port} -s ${allow_from} -j ACCEPT 2>/dev/null \
                  || iptables -I INPUT -p tcp --dport ${listen_port} -s ${allow_from} -j ACCEPT"

    echo "→ ${alias}: starting xray-poc"
    ssh "$alias" "systemctl daemon-reload && systemctl enable --now xray-poc.service && systemctl restart xray-poc.service"
    ssh "$alias" "systemctl --no-pager --lines=5 status xray-poc.service" || true
}

deploy_host ZenithOfVastness configs/zov-rendered.json 2053 82.146.35.191/32
deploy_host MaskanyaHopMsk    configs/msk-rendered.json 443  0.0.0.0/0

echo
echo "✓ deployed. Run scripts/gen-client-uri.sh to get the v2rayN URI."
echo "  Logs: ssh ZenithOfVastness journalctl -u xray-poc -f"
echo "        ssh MaskanyaHopMsk    journalctl -u xray-poc -f"
