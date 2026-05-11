# Channel C — Full TCP Tunnel via YC API Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Channel C *fetch-relay* PoC with a full TCP-multiplexing tunnel that carries arbitrary VLESS streams from a Russian client through Yandex Cloud out to ZenithOfVastness (NL) and onward to the open internet, fast enough to stream YouTube. The client uses **stock Hiddify (or any VLESS-aware client)** with a vless:// subscription URL — no custom proxy app required beyond the helper background service.

**Architecture: VLESS → yac → WSS.** Three layers stacked on top of the open-source `yac-ws-bridge` v4 transport (WTFPL, validated by author at ~20 Mbps):

1. **Outer layer (client UX):** Stock Hiddify speaks VLESS-over-WS to `127.0.0.1:1080`, where a local **helper** background service listens.
2. **Middle layer (transport):** `helper` and `adapter` (both Go binaries) wrap incoming TCP bytes (VLESS payload, opaque to them) into yac mux frames and shuttle them through YC API Gateway via the `wsSend` gRPC API (no function in data path; function only handles HELLO discovery).
3. **Inner layer (server-side termination):** On ZOV, adapter forwards bytes to a local **xray-core VLESS-WS inbound** on `127.0.0.1:10000`. xray decodes VLESS, applies routing/sniffing/UUID auth, and egresses to the internet.

```
Hiddify / v2rayN / Karing (any VLESS-WS client)
  │ TCP localhost (1080) carrying VLESS-over-WS bytes
  ▼
helper (Go, on RU client — background service) ──wsSend(gRPC)──► YC API Gateway ──WS(/_adapter)──► adapter (Go, on ZOV)
                                                  ◄──WS(/_helper)── YC API Gateway ◄──wsSend(gRPC)── adapter
                                                                    │
                                                                    │ Cloud Function (Node.js) — discovery only (HELLO)
                                                                    ▼
                                                                  adapter target: 127.0.0.1:10000
                                                                                       │ raw TCP (VLESS-WS bytes pass through)
                                                                                       ▼
                                                                                  xray-core VLESS-WS inbound (ZOV)
                                                                                       │ UUID auth, routing, geoip
                                                                                       ▼
                                                                                  internet (NL egress, IP 103.137.249.134)
```

**Why this stack vs. SOCKS5+Dante (rejected alternative):**
- **Stock client UX:** users get a vless:// URL → import into Hiddify → connect. No SOCKS5 fiddling.
- **Multi-tenancy via xray UUIDs:** one tunnel can serve N logical users (yac's "1 client per WS session" limit becomes "1 helper per device", not "1 user total").
- **xray feature set:** built-in routing (geoip:ru→direct), DNS sniffing, per-UUID stats, integrates with Marzban subscription tooling.
- **Single subscription with Channel A:** same UUID works in both VLESS+Reality (Channel A direct) and VLESS-WS (Channel C through tunnel). Hiddify auto-failovers.
- **Helper and adapter remain protocol-agnostic byte pipes** — no fork, no upstream divergence. We're just changing what `target.address` points to.

**Tech Stack:**
- Go 1.21+ (build adapter & helper from upstream — unchanged)
- Yandex Cloud: API Gateway + Cloud Function (Node.js 22)
- xray-core (already on ZOV from Channel A; we add a new inbound)
- ZOV systemd units for `maskanya-tunnel-adapter` (long-running)
- Client side: helper as systemd/launchd/scheduled task; Hiddify already installed
- Test client: macOS laptop initially; RU Android device via Hiddify-Next + helper-as-Termux for VAL-03b

**Hard constraints (from upstream README + YC docs):**
- WS connection: 60 min hard cap, 10 min idle timeout → `pingIntervalMs: 30000` mandatory.
- Max WS message: 128 KB; max frame: 32 KB. Coalescing buffer ≤ 32 KB.
- One **helper** ↔ one function ↔ one **adapter** at the yac layer. Multi-user achieved at the **xray layer** above (multiple UUIDs share one tunnel from a single device).
- For multi-device per user (e.g. user wants both phone and laptop simultaneously through Channel C): need separate function+adapter pair per device. Acceptable for PoC (1 user, 1 device); needs protocol fork for production multi-device.
- Adapter `target.address` is a single TCP destination → that destination is xray's VLESS-WS inbound, which then handles arbitrary egress.
- Yandex *may* throttle/ban this usage. Author recommends: keep traffic moderate, JS-obfuscate function source, randomize WS path names. Not blocking for PoC; flag for prod.
- **Inner-tunnel TLS: MANDATORY** (`security: "tls"`). The outer wrapper (helper↔YC and YC↔adapter) is encrypted at the transport layer (TLS to YC's WS endpoint + gRPC TLS), but YC infrastructure itself sits in the middle and could read the cleartext WS payload bytes — including under RU legal compulsion. Inner TLS at the VLESS layer prevents this: YC sees only TLS-encrypted bytes between two endpoints (helper-side xray and ZOV-side xray). We use the existing LE certificate for `panel.maskanya.animeenigma.ru` (already on ZOV via certbot, auto-renewed) — no new cert provisioning needed. Client SNI = `panel.maskanya.animeenigma.ru`; no DNS resolution happens through the tunnel for that name (client `address` is `127.0.0.1`, SNI is just a TLS-handshake string).

### Threat model — what YC can and cannot see

| YC observability | With inner TLS (this plan) |
|---|---|
| WS upgrade headers (Path, fake Host) | ✅ visible (gives away "there's a tunnel") |
| TLS ClientHello SNI | ✅ visible — `panel.maskanya.animeenigma.ru` (innocuous, our own subdomain) |
| TLS-encrypted payload bytes | ❌ opaque ciphertext |
| VLESS UUID (per-user identity) | ❌ inside TLS payload |
| Inner SNI to actual destination (youtube.com etc.) | ❌ inside TLS-of-VLESS, then encrypted again by browser's TLS to target |
| User's HTTPS page content | ❌ triple-encrypted at this point |
| Traffic volume, timing, packet sizes | ⚠️ leaks (traffic shape). Mitigation = padding/obfuscation, deferred to post-PoC |
| The fact that connection exists between specific helper and adapter | ⚠️ visible (adapter+helper conn IDs paired via function HELLO) |

The function code itself never sees data bytes (no-relay mode bypasses function for data). Even if RU government compels YC to log everything, they get TLS ciphertext, not VLESS streams.

**iOS limitation:** helper requires a user-space Go binary running as background service. iOS forbids this outside Network Extension apps that go through App Store review. **iOS users get Channel A only**; Channel C is desktop+Android only for PoC. Production iOS would require a custom Network Extension app (Apple Dev account + months of work). Documented as known limitation in Phase F.

---

## Files to Create / Modify

```
experiments/c-yc-tunnel/                                    [NEW DIR]
├── README.md                                               operator runbook
├── upstream/                                               vendored yac-ws-bridge subset
│   ├── adapter-and-helper/         (cp from /tmp clone, exclude maui-client/)
│   └── bridge-cloud/
├── adapter.config.yaml                                     ZOV-specific config
├── helper.config.yaml                                      operator-laptop config
├── spec.yaml                                               filled openapi (FUNCTION_ID, SA_ID substituted)
├── deploy-cloud.sh                                         create function + gateway via yc CLI
├── deploy-zov.sh                                           rsync upstream + adapter.config to ZOV, install systemd unit
├── teardown.sh                                             remove function/gateway, stop systemd
└── RESULTS.md                                              empirical findings (filled after Phase D/E)

ansible/roles/maskanya_tunnel/                              [NEW ROLE — only after PoC PASS]
└── (deferred to Phase F)
```

The existing `experiments/c-yc-function/` (fetch-relay PoC) is kept intact as historical record. Channel C in `.planning/REQUIREMENTS.md` (CHC-01..05) is satisfied by this new tunnel; old fetch-relay function stays deployed until tunnel function is verified, then both can coexist (different function names).

---

## Phase A — YC infrastructure (Function + API Gateway)

**Files:**
- Create: `experiments/c-yc-tunnel/upstream/` (vendored copy)
- Create: `experiments/c-yc-tunnel/spec.yaml`, `deploy-cloud.sh`

### Task A1: Vendor upstream code

- [ ] **Step 1:** Clone & copy

```bash
cd /Users/neymik/Documents/maskanya
mkdir -p experiments/c-yc-tunnel/upstream
git -C /tmp clone --depth 1 https://github.com/noiseonwires/yac-ws-bridge.git yac-ws-bridge-pinned 2>/dev/null || true
cp -R /tmp/yac-ws-bridge-pinned/adapter-and-helper experiments/c-yc-tunnel/upstream/
cp -R /tmp/yac-ws-bridge-pinned/bridge-cloud experiments/c-yc-tunnel/upstream/
echo "eb15143" > experiments/c-yc-tunnel/upstream/UPSTREAM_COMMIT
```

- [ ] **Step 2:** Verify

```bash
ls experiments/c-yc-tunnel/upstream/adapter-and-helper/cmd
ls experiments/c-yc-tunnel/upstream/bridge-cloud
cat experiments/c-yc-tunnel/upstream/UPSTREAM_COMMIT
```
Expected: `adapter helper` ; `README.md  index.js  package.json  spec.yaml` ; `eb15143`.

- [ ] **Step 3:** Commit

```bash
git add experiments/c-yc-tunnel/upstream
git commit -m "vendor yac-ws-bridge v4 @ eb15143 (WTFPL)"
```

### Task A2: Provision Cloud Function

Reuse SA from existing PoC (`maskanya-poc-c` if that's the name; otherwise create per upstream README §1). Folder: `b1gamurq8prfsf4dso64`. Function name: `maskanya-tunnel-bridge` (distinct from existing `image-thumbnailer-v2`).

- [ ] **Step 1:** Add the gateway broadcaster role (if not present)

```bash
SA_ID=$(yc iam service-account get --name maskanya-poc-c --format json | jq -r .id)
FOLDER_ID=b1gamurq8prfsf4dso64
yc resource-manager folder add-access-binding $FOLDER_ID \
  --role api-gateway.websocketBroadcaster \
  --subject serviceAccount:$SA_ID
```
Expected: success. The `wsSend` gRPC API requires this role.

- [ ] **Step 2:** Generate auth secret & save

```bash
echo "TUNNEL_AUTH_TOKEN=$(openssl rand -hex 32)" >> experiments/c-yc-tunnel/keys.sh
chmod 600 experiments/c-yc-tunnel/keys.sh
echo "experiments/c-yc-tunnel/keys.sh" >> .gitignore.local 2>/dev/null
```

- [ ] **Step 3:** Bundle and deploy function

```bash
cd experiments/c-yc-tunnel/upstream/bridge-cloud
zip -q /tmp/tunnel-fn.zip index.js package.json
yc serverless function create --name maskanya-tunnel-bridge --folder-id b1gamurq8prfsf4dso64 || true
# adapter URL will be filled in Phase B; placeholder for now
yc serverless function version create \
  --function-name maskanya-tunnel-bridge \
  --folder-id b1gamurq8prfsf4dso64 \
  --runtime nodejs22 \
  --entrypoint index.handler \
  --memory 128m \
  --execution-timeout 10s \
  --concurrency 16 \
  --service-account-id $SA_ID \
  --source-path /tmp/tunnel-fn.zip \
  --environment "AUTH_TOKEN=$TUNNEL_AUTH_TOKEN,ADAPTER_URL=http://placeholder:3001"
```
Expected: returns version ID.

- [ ] **Step 4:** Make publicly invokable (toggle in console UI; CLI requires `iam.editor` which our SA lacks — see existing RESULTS.md)

```bash
echo "→ open YC console: Cloud Functions → maskanya-tunnel-bridge → toggle 'Public function' ON"
```

- [ ] **Step 5:** Capture function ID and commit deploy script

```bash
FUNCTION_ID=$(yc serverless function get --name maskanya-tunnel-bridge --folder-id b1gamurq8prfsf4dso64 --format json | jq -r .id)
echo "FUNCTION_ID=$FUNCTION_ID"
```

Write `experiments/c-yc-tunnel/deploy-cloud.sh` capturing the above as a re-runnable script (parameterized via `keys.sh` source).

```bash
git add experiments/c-yc-tunnel/deploy-cloud.sh
git commit -m "channel-c-tunnel: deploy script for YC function"
```

### Task A3: Provision API Gateway

- [ ] **Step 1:** Render spec from template

```bash
cd experiments/c-yc-tunnel
sed -e "s|\${FUNCTION_ID}|$FUNCTION_ID|g" \
    -e "s|\${SERVICE_ACCOUNT_ID}|$SA_ID|g" \
    upstream/bridge-cloud/spec.yaml > spec.yaml
```
Expected: `spec.yaml` exists, no `${...}` placeholders remain (`grep '\${' spec.yaml` returns nothing).

- [ ] **Step 2:** Create gateway

```bash
yc serverless api-gateway create \
  --name maskanya-tunnel-gw \
  --folder-id b1gamurq8prfsf4dso64 \
  --spec spec.yaml
```
Expected: success.

- [ ] **Step 3:** Capture gateway domain

```bash
GW_DOMAIN=$(yc serverless api-gateway get --name maskanya-tunnel-gw --folder-id b1gamurq8prfsf4dso64 --format json | jq -r .domain)
echo "GW_DOMAIN=$GW_DOMAIN"
echo "GW_DOMAIN=$GW_DOMAIN" >> experiments/c-yc-tunnel/keys.sh
```
Expected: a `*.apigw.yandexcloud.net` hostname.

- [ ] **Step 4:** Smoke-test the WS endpoint exists (auth will fail — that's fine; we just want a 1xx upgrade response)

```bash
brew install websocat 2>/dev/null || true
echo '{"type":"hello"}' | websocat --text "wss://$GW_DOMAIN/_adapter" --max-messages 1 2>&1 | head
```
Expected: TLS connection succeeds, WS upgrade succeeds, function returns auth-rejection (we have no token in HELLO — that's success criteria for "endpoint reachable").

- [ ] **Step 5:** Commit spec.yaml (without secrets)

```bash
# spec.yaml has FUNCTION_ID and SA_ID inlined — these are folder-scoped and not secret per se,
# but cleaner to keep the template separate. Commit the rendered spec for reproducibility.
git add experiments/c-yc-tunnel/spec.yaml experiments/c-yc-tunnel/deploy-cloud.sh
git commit -m "channel-c-tunnel: api gateway spec & deploy script"
```

---

## Phase B — Adapter on ZOV with xray VLESS-WS inbound

**Files:**
- Create: `experiments/c-yc-tunnel/adapter.config.yaml`
- Create: `experiments/c-yc-tunnel/xray-tunnel-inbound.json`
- Create: `experiments/c-yc-tunnel/deploy-zov.sh`
- Modify on ZOV: extend existing xray config with new VLESS-WS inbound; install systemd unit for adapter

### Task B1: Set up xray VLESS-WS inbound on ZOV (loopback-only)

The existing xray service on ZOV (`xray-maskanya` per memory `project_zov_bootstrap_state.md`) handles Channel A. We add a **second xray inbound** for the tunnel endpoint. Two deployment options:
  - **Option B1.A (preferred):** Add a new inbound to the existing `xray-maskanya` config — single xray process, simpler ops.
  - **Option B1.B:** Stand up a second xray process `xray-tunnel` with its own config and systemd unit — isolation but more moving parts.

Choose **B1.A** for PoC. Production may revisit.

- [ ] **Step 1:** Check current ZOV state — confirm 127.0.0.1:10000 is free and inspect existing xray config

```bash
ssh ZenithOfVastness -- 'ss -lnt | grep -E ":10000\\b" || echo PORT_FREE'
ssh ZenithOfVastness -- 'cat /etc/xray/config.json | jq ".inbounds[].port" 2>/dev/null'
ssh ZenithOfVastness -- 'systemctl status xray-maskanya --no-pager | head -10'
```
Expected: `PORT_FREE`; current inbounds listed (should include `:443` for Channel A); xray-maskanya `active (running)`.

- [ ] **Step 2:** Generate a fresh UUID for the tunnel-bound user

```bash
TUNNEL_UUID=$(ssh ZenithOfVastness -- 'cat /proc/sys/kernel/random/uuid')
echo "TUNNEL_UUID=$TUNNEL_UUID" >> experiments/c-yc-tunnel/keys.sh
echo "→ generated tunnel UUID: $TUNNEL_UUID"
```

- [ ] **Step 3:** Locate existing LE cert for `panel.maskanya.animeenigma.ru` and read paths

```bash
ssh ZenithOfVastness -- 'ls -la /etc/letsencrypt/live/panel.maskanya.animeenigma.ru/'
```
Expected: `cert.pem fullchain.pem privkey.pem chain.pem` symlinks.

If subdomain different — adjust to whatever LE-managed subdomain is available. We need a real CA-signed cert because xray client validates against system trust store; self-signed would force `allowInsecure=true` which opens MITM by YC.

- [ ] **Step 4:** Construct the new inbound JSON snippet with TLS

Write `experiments/c-yc-tunnel/xray-tunnel-inbound.json`:

```json
{
  "listen": "127.0.0.1",
  "port": 10000,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "REPLACE_WITH_TUNNEL_UUID",
        "flow": ""
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "security": "tls",
    "tlsSettings": {
      "serverName": "panel.maskanya.animeenigma.ru",
      "alpn": ["http/1.1"],
      "minVersion": "1.2",
      "certificates": [
        {
          "certificateFile": "/etc/letsencrypt/live/panel.maskanya.animeenigma.ru/fullchain.pem",
          "keyFile": "/etc/letsencrypt/live/panel.maskanya.animeenigma.ru/privkey.pem"
        }
      ]
    },
    "wsSettings": {
      "path": "/maskanya-tun",
      "headers": {}
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly": false
  },
  "tag": "in-tunnel"
}
```

**Why TLS is mandatory here:** even though `127.0.0.1:10000` is loopback-only on ZOV, the bytes that reach this listener flow through YC infrastructure as plaintext WS payload. With `security: "none"`, YC sees VLESS handshakes, UUIDs, inner SNIs, response bodies. With `security: "tls"`, YC sees only TLS ClientHello + opaque ciphertext. See Threat Model section above for full breakdown.

**Permission caveat:** xray-maskanya runs as user `xray-maskanya` (per memory `project_zov_bootstrap_state.md`). It needs read access to the LE privkey. Standard certbot install gives `/etc/letsencrypt/live/.../privkey.pem` mode `600 root:root`. We'll grant read in Step 5.

- [ ] **Step 5:** Grant xray-maskanya group read access to the LE privkey

```bash
ssh ZenithOfVastness -- '
  # ensure the cert dir is traversable
  chmod o+x /etc/letsencrypt/live /etc/letsencrypt/archive
  # grant group read on the actual key file (follow symlinks)
  REAL_KEY=$(readlink -f /etc/letsencrypt/live/panel.maskanya.animeenigma.ru/privkey.pem)
  chgrp xray-maskanya "$REAL_KEY"
  chmod 640 "$REAL_KEY"
  ls -la "$REAL_KEY"
'
```
Expected: privkey now readable by xray-maskanya group. Note: certbot renew may reset perms — add a deploy-hook later (Phase F).

- [ ] **Step 6:** Merge into ZOV's xray config (atomic, with rollback)

```bash
# 1. snapshot
TS=$(date -u +%Y%m%d-%H%M%S)
ssh ZenithOfVastness -- "cp /etc/xray/config.json /etc/xray/config.json.pre-tunnel-bak.$TS"
echo "backup: /etc/xray/config.json.pre-tunnel-bak.$TS"

# 2. fetch current config locally
scp ZenithOfVastness:/etc/xray/config.json /tmp/xray-current.json

# 3. inject new inbound with our UUID
source experiments/c-yc-tunnel/keys.sh
jq --arg uuid "$TUNNEL_UUID" '.settings.clients[0].id = $uuid' \
   experiments/c-yc-tunnel/xray-tunnel-inbound.json > /tmp/xray-tunnel-inbound-with-uuid.json
jq --slurpfile inb /tmp/xray-tunnel-inbound-with-uuid.json \
   '.inbounds += $inb' \
   /tmp/xray-current.json > /tmp/xray-merged.json

# 4. push and reload
scp /tmp/xray-merged.json ZenithOfVastness:/etc/xray/config.json
ssh ZenithOfVastness -- 'chown xray-maskanya:xray-maskanya /etc/xray/config.json && systemctl reload xray-maskanya 2>/dev/null || systemctl restart xray-maskanya'
sleep 2
ssh ZenithOfVastness -- 'systemctl status xray-maskanya --no-pager | head -10'
ssh ZenithOfVastness -- 'ss -lnt | grep -E ":10000\\b"'
```
Expected: xray active; `127.0.0.1:10000` listening.

**Rollback:** `ssh ZenithOfVastness -- "cp /etc/xray/config.json.pre-tunnel-bak.$TS /etc/xray/config.json && systemctl reload xray-maskanya"`

- [ ] **Step 7:** Verify TLS handshake on the inbound

```bash
ssh ZenithOfVastness -- 'echo | openssl s_client -connect 127.0.0.1:10000 -servername panel.maskanya.animeenigma.ru 2>&1 | head -20'
```
Expected: cert chain printed, issuer = `Let's Encrypt`, subject CN = `panel.maskanya.animeenigma.ru`, handshake completes (then closes — no inner WS upgrade attempted from openssl).

### Task B2: Build adapter binary on ZOV

- [ ] **Step 1:** Push source to ZOV

```bash
rsync -aP experiments/c-yc-tunnel/upstream/adapter-and-helper/ \
    ZenithOfVastness:/opt/maskanya-tunnel/src/
```
Expected: files copied.

- [ ] **Step 2:** Install Go on ZOV (if missing) and build

```bash
ssh ZenithOfVastness -- 'which go || (apt-get install -y golang-1.21-go && ln -sf /usr/lib/go-1.21/bin/go /usr/local/bin/go)'
ssh ZenithOfVastness -- 'cd /opt/maskanya-tunnel/src && go build -o /opt/maskanya-tunnel/bin/adapter ./cmd/adapter'
ssh ZenithOfVastness -- '/opt/maskanya-tunnel/bin/adapter --help 2>&1 | head -5 || /opt/maskanya-tunnel/bin/adapter /dev/null 2>&1 | head -5'
```
Expected: binary built, runs (will exit on bad config — fine).

### Task B3: Write adapter config & systemd unit

- [ ] **Step 1:** Build local config from template

```bash
source experiments/c-yc-tunnel/keys.sh
cat > /tmp/adapter.config.yaml <<EOF
bridge:
  url: "wss://$GW_DOMAIN/_adapter"
  authToken: "$TUNNEL_AUTH_TOKEN"
  reconnect:
    initialDelayMs: 1000
    maxDelayMs: 30000
    backoffMultiplier: 2
  pingIntervalMs: 30000

target:
  address: "127.0.0.1:10000"

http:
  listenPort: 3001

writeCoalescing:
  enabled: true
  delayMs: 50

wsApi:
  mode: "grpc"

logging:
  level: "info"
EOF
scp /tmp/adapter.config.yaml ZenithOfVastness:/opt/maskanya-tunnel/adapter.config.yaml
ssh ZenithOfVastness -- 'chmod 600 /opt/maskanya-tunnel/adapter.config.yaml'
```

- [ ] **Step 2:** Update Function `ADAPTER_URL` to point to real ZOV adapter HTTP endpoint
We expose adapter HTTP on `127.0.0.1:3001` only (firewall closed publicly), so the Function (running in YC) cannot reach it directly. Two options:
  - **Simpler:** open `:3001` to public via the existing nginx_stream demuxer or a dedicated port. Auth via `Bearer $TUNNEL_AUTH_TOKEN`.
  - **Per upstream README:** ADAPTER_URL is consulted only at function cold-start to recover state when there are multiple function instances. With `concurrency: 16` and low traffic, cold-start recovery is rarely needed. Acceptable risk for PoC: leave ADAPTER_URL as placeholder; restart adapter+helper on any function-instance churn.

For PoC: leave placeholder. Document in RESULTS.md.

- [ ] **Step 3:** Write systemd unit

```bash
ssh ZenithOfVastness -- 'cat > /etc/systemd/system/maskanya-tunnel-adapter.service' <<'EOF'
[Unit]
Description=Maskanya Channel C tunnel adapter
After=network-online.target xray-maskanya.service
Wants=network-online.target
Requires=xray-maskanya.service

[Service]
Type=simple
WorkingDirectory=/opt/maskanya-tunnel
ExecStart=/opt/maskanya-tunnel/bin/adapter /opt/maskanya-tunnel/adapter.config.yaml
Restart=always
RestartSec=5
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
ssh ZenithOfVastness -- 'systemctl daemon-reload && systemctl enable --now maskanya-tunnel-adapter'
sleep 3
ssh ZenithOfVastness -- 'systemctl status maskanya-tunnel-adapter --no-pager | head -20 && journalctl -u maskanya-tunnel-adapter -n 30 --no-pager'
```
Expected: adapter logs show successful WS connect to gateway and HELLO ack.

- [ ] **Step 4:** Commit adapter config (without secrets) & deploy script

```bash
sed 's/authToken:.*/authToken: "REDACTED — see keys.sh"/' /tmp/adapter.config.yaml > experiments/c-yc-tunnel/adapter.config.yaml
git add experiments/c-yc-tunnel/adapter.config.yaml
# write deploy-zov.sh from the above ssh commands
git add experiments/c-yc-tunnel/deploy-zov.sh
git commit -m "channel-c-tunnel: adapter on ZOV pointing at xray VLESS-WS inbound"
```

---

## Phase C — Helper on operator laptop

**Files:**
- Create: `experiments/c-yc-tunnel/helper.config.yaml`

### Task C1: Build helper

- [ ] **Step 1:** Build for current host (macOS arm64)

```bash
cd experiments/c-yc-tunnel/upstream/adapter-and-helper
go build -o /tmp/maskanya-helper ./cmd/helper
/tmp/maskanya-helper /dev/null 2>&1 | head -3
```
Expected: built; runs (errors on bad config — fine).

### Task C2: Write helper config

- [ ] **Step 1:** Render config

```bash
source experiments/c-yc-tunnel/keys.sh
cat > /tmp/helper.config.yaml <<EOF
bridge:
  url: "wss://$GW_DOMAIN/_helper"
  authToken: "$TUNNEL_AUTH_TOKEN"
  reconnect:
    initialDelayMs: 1000
    maxDelayMs: 30000
    backoffMultiplier: 2
  pingIntervalMs: 30000

listen:
  address: "127.0.0.1:1080"

writeCoalescing:
  enabled: true
  delayMs: 50

wsApi:
  mode: "grpc"
  relay: false

logging:
  level: "info"
EOF
```

- [ ] **Step 2:** Run helper in foreground

```bash
/tmp/maskanya-helper /tmp/helper.config.yaml &
HELPER_PID=$!
sleep 5
# expect log lines like: "connected to bridge", "HELLO ack", "adapter discovered: <conn-id>"
```
Expected: helper logs show paired with adapter.

- [ ] **Step 3:** Commit helper config (sanitized)

```bash
sed 's/authToken:.*/authToken: "REDACTED — see keys.sh"/' /tmp/helper.config.yaml > experiments/c-yc-tunnel/helper.config.yaml
git add experiments/c-yc-tunnel/helper.config.yaml
git commit -m "channel-c-tunnel: helper config template"
```

---

## Phase D — End-to-end empirical (operator side)

### Task D1: Generate vless:// subscription URL

The client side needs a standard VLESS URI pointing at `127.0.0.1:1080` (where helper listens). The URI is opaque to helper — bytes inside are decoded by xray on ZOV.

- [ ] **Step 1:** Generate URI via helper script

Create `experiments/c-yc-tunnel/gen-client-uri.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/keys.sh"

# vless://<UUID>@<host>:<port>?type=ws&path=/maskanya-tun&security=tls&sni=<sni>&fp=chrome&alpn=http/1.1#<remark>
# - host=127.0.0.1, port=1080 → helper's listen
# - security=tls + sni=panel.maskanya.animeenigma.ru → inner TLS to ZOV xray (cert validated against system trust store)
# - fp=chrome → uTLS chrome fingerprint on ClientHello (mimics Chrome — anti-fingerprint, not strictly needed inside tunnel but free win)
# - alpn=http/1.1 → match xray inbound's alpn list
URI="vless://${TUNNEL_UUID}@127.0.0.1:1080?type=ws&path=%2Fmaskanya-tun&security=tls&sni=panel.maskanya.animeenigma.ru&fp=chrome&alpn=http%2F1.1&encryption=none#Maskanya-ChannelC-tunnel"
echo "$URI"
```

```bash
chmod +x experiments/c-yc-tunnel/gen-client-uri.sh
URI=$(./experiments/c-yc-tunnel/gen-client-uri.sh)
echo "$URI"
echo "$URI" | qrencode -t ANSI 2>/dev/null || echo "(install qrencode for QR)"
```
Expected: a valid `vless://...#Maskanya-ChannelC-tunnel` URI.

### Task D2: Import URI into xray-core CLI client (operator-side smoke test)

Hiddify-Next on macOS works but is GUI-only — for scriptable verification we use the same xray binary that Channel A operator-tests use (`/opt/homebrew/bin/xray` per existing setup).

- [ ] **Step 1:** Generate xray client config from URI

```bash
mkdir -p /tmp/maskanya-client
cat > /tmp/maskanya-client/config.json <<EOF
{
  "log": {"loglevel": "info"},
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {"udp": false}
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "127.0.0.1",
          "port": 1080,
          "users": [{"id": "${TUNNEL_UUID}", "encryption": "none"}]
        }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "panel.maskanya.animeenigma.ru",
          "alpn": ["http/1.1"],
          "fingerprint": "chrome",
          "allowInsecure": false
        },
        "wsSettings": {"path": "/maskanya-tun"}
      },
      "tag": "tunnel-out"
    }
  ]
}
EOF
xray -test -config /tmp/maskanya-client/config.json
```
Expected: `Configuration OK.`

### Task D3: Run client xray + helper, smoke-test through

- [ ] **Step 1:** Make sure helper from Phase C is still running (`/tmp/maskanya-helper /tmp/helper.config.yaml &`)

- [ ] **Step 2:** Start xray client

```bash
xray -config /tmp/maskanya-client/config.json &
XRAY_PID=$!
sleep 2
ss -lnt | grep ":10808" && echo "xray socks ready"
```

- [ ] **Step 3:** Curl through the full chain

```bash
curl -s --socks5 127.0.0.1:10808 -m 30 https://ifconfig.me
```
Expected: `103.137.249.134` (ZOV NL IP). Data path:
```
curl → xray-socks(10808) → xray VLESS-WS-TLS outbound
       → opens TCP to 127.0.0.1:1080 (helper)
       → does TLS handshake to "panel.maskanya.animeenigma.ru" through tunnel
       → bytes stream (TLS-encrypted) flow through helper → wsSend → YC → adapter
       → adapter opens TCP to 127.0.0.1:10000 (ZOV xray VLESS-WS-TLS inbound)
       → ZOV xray terminates TLS, validates VLESS UUID, extracts target = ifconfig.me
       → outbound TCP to ifconfig.me, returns Russian-invisible IP
```
YC infra in the middle saw only TLS ciphertext flowing through wsSend frames.

If timeout/empty → check in order: (a) xray client log for connect errors to 127.0.0.1:1080, (b) helper log for HELLO+pair status, (c) adapter log for WS connect to YC, (d) ZOV xray log (`journalctl -u xray-maskanya -f`) for VLESS handshake.

### Task D4: HTTPS site

- [ ] **Step 1:**

```bash
curl -s --socks5 127.0.0.1:10808 -m 30 https://www.youtube.com -o /tmp/yt.html
wc -c /tmp/yt.html
grep -c '<title>YouTube</title>' /tmp/yt.html
```
Expected: ≥10000 bytes; `1`.

### Task D5: YouTube video streaming via Hiddify (or Firefox SOCKS through xray)

Two paths:

**5A (Hiddify):** Import the vless:// URI into Hiddify-Next on macOS, toggle connect, watch YouTube video. This is the production-realistic UX path.

**5B (Firefox via xray socks):** Faster to script.
```
Firefox → Network Settings → Manual proxy:
  SOCKS Host: 127.0.0.1   Port: 10808   SOCKS v5
  Proxy DNS when using SOCKS v5: ON
```

- [ ] **Step 1:** Open `https://youtube.com`, play a 4–5 minute video at 720p.

- [ ] **Step 2:** Observe:
- Video plays without rebuffering for ≥3 min straight
- Adapter journal: data frames flowing (`journalctl -u maskanya-tunnel-adapter -f`)
- ZOV xray log shows VLESS connections accepted with our UUID

Expected: smooth 720p playback. If rebuffers heavily → throughput too low; consider tweaking `writeCoalescing.delayMs` (try 30 ms or 80 ms) and/or `pingIntervalMs`.

### Task D6: Throughput measurement

- [ ] **Step 1:**

```bash
time curl -s --socks5 127.0.0.1:10808 -o /dev/null https://speed.cloudflare.com/__down?bytes=104857600
```
Expected: 100 MB downloaded in <60s → ≥13 Mbps. Per upstream, ~20 Mbps achievable; with NL adapter (further from YC RU edge) expect 5–15 Mbps. VLESS overhead vs raw SOCKS5 is <5% so we should be in a similar range to the original Dante-based estimate.

- [ ] **Step 2:** Sustained 5-min test

```bash
for i in $(seq 1 5); do
  curl -s --socks5 127.0.0.1:10808 -o /dev/null -w "$i: %{time_total}s %{speed_download}B/s\n" \
    https://speed.cloudflare.com/__down?bytes=10485760
  sleep 60
done
```
Expected: stable speeds; no auto-disconnect at the 10-min mark (yac helper reconnects transparently if YC closes the WS).

### Task D7: Record D-results

- [ ] **Step 1:** Write `experiments/c-yc-tunnel/RESULTS.md` with:
  - operator IP / ASN
  - measured throughput
  - YouTube playback verdict (Hiddify path 5A, Firefox path 5B, or both)
  - any errors observed
  - YC function invocation count for the session (`yc serverless function get --name maskanya-tunnel-bridge ...` shows metrics — should be near zero for data path; only HELLO and reconnects)

```bash
git add experiments/c-yc-tunnel/RESULTS.md experiments/c-yc-tunnel/gen-client-uri.sh
git commit -m "channel-c-tunnel: operator-side VLESS empirical PASS/FAIL"
```

---

## Phase E — RU client test

The Go helper runs anywhere (Linux/macOS/Windows). For Russian end-user testing:

### Task E1: Cross-compile helper for RU client OS

- [ ] **Step 1:**

```bash
cd experiments/c-yc-tunnel/upstream/adapter-and-helper
GOOS=windows GOARCH=amd64 go build -o /tmp/maskanya-helper.exe ./cmd/helper
GOOS=linux GOARCH=amd64 go build -o /tmp/maskanya-helper.linux ./cmd/helper
ls -la /tmp/maskanya-helper*
```
Expected: binaries built.

### Task E2: Bundle Windows helper + Hiddify-importable VLESS URI

```bash
mkdir -p /tmp/maskanya-helper-bundle
cp /tmp/maskanya-helper.exe /tmp/maskanya-helper-bundle/
cp /tmp/helper.config.yaml /tmp/maskanya-helper-bundle/
URI=$(./experiments/c-yc-tunnel/gen-client-uri.sh)
echo "$URI" > /tmp/maskanya-helper-bundle/vless.txt
qrencode -o /tmp/maskanya-helper-bundle/vless-qr.png "$URI"

cat > /tmp/maskanya-helper-bundle/RUN.txt <<'EOF'
Channel C — туннель через Yandex Cloud для случая когда обычный VPN зарезали.

УСТАНОВКА (один раз):
  1. Распакуй эту папку в постоянное место (например C:\maskanya-helper\).
  2. Открой PowerShell ОТ ИМЕНИ АДМИНИСТРАТОРА в этой папке.
  3. Запусти: schtasks /Create /SC ONLOGON /TN "MaskanyaHelper" /TR "%CD%\maskanya-helper.exe %CD%\helper.config.yaml" /RL HIGHEST
     Это поставит helper в автозапуск. Перезагрузись или запусти helper вручную сейчас:
     .\maskanya-helper.exe .\helper.config.yaml
     (оставь окно открытым в первый раз, чтобы видеть лог)

ПОДКЛЮЧЕНИЕ ЧЕРЕЗ HIDDIFY:
  4. Открой Hiddify-Next.
  5. Add profile → "Import from clipboard" (предварительно скопируй URL из vless.txt)
     ИЛИ "Import from QR code" → отсканируй vless-qr.png
  6. Включи профиль "Maskanya-ChannelC-tunnel"
  7. Hiddify подключится локально к 127.0.0.1:1080 — это helper, который туннелирует трафик через YC

ПРОВЕРКА:
  https://ifconfig.me должен показать 103.137.249.134 (Нидерланды).
  Если показывает твой обычный IP — Hiddify не активирован или helper не запущен.
EOF

zip -j /tmp/maskanya-helper-bundle.zip /tmp/maskanya-helper-bundle/*
ls -la /tmp/maskanya-helper-bundle.zip
```

### Task E3: Bundle Android helper + Hiddify-Next subscription

Android-вариант сложнее: helper нужно держать как foreground service. Два пути:
- **E3.A (Termux):** для технических юзеров — Termux + cron + helper-binary как `linux/arm64`. Гарантированно работает, но требует возни с Termux:Boot и Termux:API.
- **E3.B (MAUI app):** собрать `maui-client/` из upstream под Android — это полноценный VPN-клиент с встроенным helper. Юзер устанавливает APK, никаких других зависимостей.

Для PoC берём E3.B как user-friendly путь:

```bash
cd experiments/c-yc-tunnel/upstream/maui-client
dotnet workload install maui-android 2>&1 | tail -5
dotnet publish -f net8.0-android -c Release -o /tmp/maui-out 2>&1 | tail -10
ls /tmp/maui-out/*.apk
```
Ожидаем: APK файл. Если dotnet/maui-android workload не установлен и установка падает — fallback на E3.A.

В bundle: APK + JSON config (содержит GW_DOMAIN + TUNNEL_AUTH_TOKEN) + vless.txt + vless-qr.png + RUN_ANDROID.txt с инструкциями.

### Task E4: RU тестер выполняет и докладывает

User-side. Capture in RESULTS.md:
- какая RU ISP / регион
- helper подключается к YC? (TLS / WS handshake fail под whitelist? Должно работать — `*.apigw.yandexcloud.net` в YC whitelist)
- Hiddify импорт VLESS URL прошёл успешно?
- ifconfig.me через Hiddify VPN показывает `103.137.249.134`?
- YouTube test verdict
- Любые специфичные failures (с логами helper)

---

## Phase F — Document & integrate

### Task F1: Update spec & STATE

- [ ] **Step 1:** Update `docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md` Channel C section: replace fetch-relay description with tunnel architecture; reference this plan and `yac-ws-bridge` upstream.

- [ ] **Step 2:** Update `.planning/STATE.md`:
- Note that VAL-03 fetch-relay is superseded
- Add CHC-tunnel completion record with throughput/YouTube verdicts

- [ ] **Step 3:** Mark CHC-01..05 in `.planning/REQUIREMENTS.md` as satisfied (or note gaps — e.g. CHC-04 multi-tenancy is a known limitation).

```bash
git add docs/superpowers/specs .planning
git commit -m "channel-c-tunnel: update spec/state with tunnel architecture"
```

### Task F2: Risks & follow-ups doc

- [ ] **Step 1:** Append to `experiments/c-yc-tunnel/RESULTS.md`:
- **Yac single-client limit at WS layer** → at the xray layer above, multiple UUIDs share one tunnel from the same device (multi-app on one phone OK). For multi-device per user, need separate function+adapter pair per device, or fork yac protocol to add per-stream session-IDs.
- **Yandex policy risk:** unknown TTL before account flagged; mitigate by JS-obfuscating function and randomizing path names (`/_adapter` → `/_a${random}`)
- **NL latency penalty:** adapter in NL not in RU → +40-80ms RTT vs upstream's optimal RU adapter scenario
- **UDP not tunneled:** TCP-only. YouTube uses TCP fallback when QUIC fails. WebRTC voice/video and games won't work through Channel C — use Channel A for those.
- **ADAPTER_URL placeholder:** function cold-start state-recovery breaks — mitigated by manual restart on function instance churn (rare at 16 concurrency).
- **iOS unsupported:** helper requires user-space background daemon; iOS forbids outside Network Extension apps. iOS users get Channel A only.
- **Traffic-shape leaks:** YC sees TLS-encrypted bytes but can still infer connection patterns from packet sizes/timing. Padding/obfuscation deferred to post-PoC.

### Task F3: Cert renewal hook

certbot renew runs nightly via systemd timer. When it renews `panel.maskanya.animeenigma.ru`, it generates a fresh privkey with default mode `600 root:root` — losing the `xray-maskanya` group read we set in Phase B Task B1 Step 5. Without a hook, xray will silently use the old cert until restart, then fail to load the new one.

- [ ] **Step 1:** Install certbot deploy-hook on ZOV

```bash
ssh ZenithOfVastness -- 'cat > /etc/letsencrypt/renewal-hooks/deploy/maskanya-tunnel-perms.sh' <<'EOF'
#!/bin/bash
# Re-grant xray-maskanya group read on the privkey after certbot renew.
# RENEWED_LINEAGE is set by certbot to /etc/letsencrypt/live/<domain>
set -e
if [ -z "$RENEWED_LINEAGE" ]; then exit 0; fi
case "$RENEWED_LINEAGE" in
  */panel.maskanya.animeenigma.ru)
    REAL_KEY=$(readlink -f "$RENEWED_LINEAGE/privkey.pem")
    chgrp xray-maskanya "$REAL_KEY"
    chmod 640 "$REAL_KEY"
    systemctl reload xray-maskanya
    ;;
esac
EOF
ssh ZenithOfVastness -- 'chmod +x /etc/letsencrypt/renewal-hooks/deploy/maskanya-tunnel-perms.sh'
```

- [ ] **Step 2:** Test hook by forcing a dry-run renew

```bash
ssh ZenithOfVastness -- 'certbot renew --dry-run --cert-name panel.maskanya.animeenigma.ru 2>&1 | tail -20'
```
Expected: dry-run completes; hook would have fired.

```bash
git add experiments/c-yc-tunnel/RESULTS.md
# the deploy-hook script — also save a copy in repo for ansible-ification later
mkdir -p experiments/c-yc-tunnel/zov-files
scp ZenithOfVastness:/etc/letsencrypt/renewal-hooks/deploy/maskanya-tunnel-perms.sh \
    experiments/c-yc-tunnel/zov-files/le-renewal-hook.sh
git add experiments/c-yc-tunnel/zov-files/
git commit -m "channel-c-tunnel: production risks, known limitations, cert renewal hook"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ Goal (full VLESS tunnel, YouTube-capable, Hiddify-compatible) → Phase D, especially D3+D5
- ✅ Architecture diagram + threat model → top of plan
- ✅ TLS-inside-tunnel (YC sees only ciphertext) → Phase B Task B1 Step 4 + Threat Model section
- ✅ Stock client compatibility (Hiddify import flow) → Phase D Task D1 (URI generator) + Phase E (bundling)
- ✅ Multi-tenancy via xray UUIDs (above yac single-client limit) → Architecture section + F2
- ⚠️ Phase 1 (port discipline / SNI demuxer) is **not** in this plan — Channel C runs over `*.apigw.yandexcloud.net` :443 (YC whitelist) independently of ZOV port discipline. ZOV side uses outbound WS only. No inbound port exposure changes.
- ⚠️ iOS deferred — known limitation per F2.

**Placeholder check:** No `TBD` / `implement later` / `TODO` left. ADAPTER_URL placeholder is intentional and documented.

**Type/identifier consistency:** `maskanya-tunnel-bridge` (function), `maskanya-tunnel-gw` (gateway), `maskanya-tunnel-adapter` (systemd unit), `/opt/maskanya-tunnel/` (ZOV path), `127.0.0.1:10000` (xray VLESS-WS-TLS inbound), `127.0.0.1:1080` (helper listen), `127.0.0.1:10808` (operator-side xray socks for testing) — used consistently across phases.

**Time estimate:** Phase A ~30 min (mostly YC console toggle waiting). Phase B ~30 min (xray inbound merge + cert perms). Phase C ~10 min. Phase D ~30 min (incl. 5-min YouTube observation). Phase E depends on RU tester availability + MAUI build (~1h if dotnet/maui-android workload not pre-installed). Phase F ~30 min. **Total operator-side: ~2.5 hours of active work.**

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-11-channel-c-yc-tunnel.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per phase, review between phases, fast iteration. Best when you want me to drive end-to-end without supervision.

**2. Inline Execution** — Execute phases in this session using `executing-plans`, batch execution with checkpoints. Best when you want to watch each step and intervene if something behaves oddly on ZOV (since ZOV has 13 production sites we don't want to disturb).

**Recommendation:** Inline for Phases A–B (touches ZOV), Subagent for Phases C–D (laptop-only). Phase E is operator-side anyway.

**Which approach?**
