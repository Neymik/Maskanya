# Maskanya — Three-Channel VPN Design

**Date:** 2026-05-08
**Status:** Draft — replaces `2026-04-17-vless-reality-multihop-vpn-design.md` after the May 2026 regulatory shift.
**Hosts:** unchanged — `ZenithOfVastness` (NL, dual-role mgmt+exit) and `MaskanyaHopMsk` (Moscow, entry). New work is a protocol-stack and tooling pivot on the existing two boxes; no new VPS, no provider migration.

## Why this spec exists

The April 17 design assumed a single transport (VLESS+Reality+Vision over TCP/443) on cheap RU entry + foreign exit. Between mid-Feb and early May 2026 the RU side hardened in three ways that break that assumption:

1. **Behavioral DPI** — TSPU now classifies post-handshake traffic geometry (packet sizes, timing, up/down ratios) and matches it against the SNI's expected service. Reality masks the handshake; it does not mask the payload, so a long-lived VLESS-tunnel-over-TLS to `samsung.com` looks nothing like real `samsung.com`.
2. **Whitelist-mode L3 filtering** — RKN piloted, in April 2026, a CIDR whitelist (~63K IPs out of ~46M RU addresses) with default-drop. When this regime is active in a region or globally, a generic Moscow VPS IP gets dropped at L3 before any DPI runs. Yandex Cloud (~13K IPs) is in the whitelist; FirstVDS (where `MaskanyaHopMsk` lives) is not.
3. **May 1 cross-border traffic charges** — RU mobile carriers now bill ~100–150 ₽/GB above 15 GB/month for traffic egressing to foreign IPs. Tunneling everything to NL is now economically painful for users.

The user has decided not to migrate hosts. Therefore we accept that **the single-VLESS-channel model cannot survive a whitelist-mode event**, and we add two whitelist-resident escape channels alongside it.

## Goals

1. Keep VLESS+Reality as the primary, fast, low-cost channel — but rebuild it to current 2026 standards (XHTTP, uTLS chrome fingerprint, whitelist-friendly SNI, real-server fallback) so it survives the day-to-day regime, not just the easy days.
2. Provide a whitelist-mode escape via **Yandex Cloud Functions** (HTTP-tunneled). Endpoint IP is structurally whitelisted; works when MSK gets dropped at L3.
3. Provide a worst-case escape via **WebRTC over Yandex Telemost** (olcRTC pattern). Slow but uses Telemost's permanently whitelisted SFU; survives even if RKN tightens further.
4. Single user/quota source of truth (Marzban) across all three channels.
5. Clients automatically pick the live channel; no operator handholding for routine outages.
6. Keep the existing AmneziaWG control mesh, secrets layout, monitoring, and ZOV preservation contract.

## Non-goals (Phase 1)

- No new hosts. No migration of MSK to YC/VK Cloud/Timeweb.
- No automatic transport rotation between Reality SNIs/short-IDs (operator does this manually for now).
- No mobile-native client. Channel B and C require a desktop companion app; mobile use is best-effort via existing v2rayN/Hiddify clones for Channel A only.
- No multi-region exit. ZOV stays the only exit until `MaskanyaExitKZ1` is provisioned (separate phase, KZ exit was already in the v1 spec and is paused).
- No anonymous public registration. Invite-only stays.

## Threat model — May 2026

| Threat | Layer | Mitigated by |
|---|---|---|
| TLS fingerprint match (JA3/JA4 → Go crypto/tls) | L7 / DPI | Channel A: `fingerprint: "chrome"` (uTLS) on every Reality block |
| Active probing of Reality `dest:` | L7 / DPI | Channel A: `dest: storage.yandex.net:443` (real Yandex CDN responds with real cert) + per-user shortIds |
| Behavioral classifier on post-handshake traffic | L7 / DPI | Channel A: XHTTP transport (mode=auto, xPaddingBytes 100-1000, randomized path) — request/response geometry mimics HTTP/2 |
| SNI in L7 blacklist | L7 / DPI | Channel A: SNI = `storage.yandex.net` / `yastatic.net` (whitelist-CDN, can't be blacklisted without breaking Yandex) |
| Whitelist-mode L3 default-drop on MSK IP | L3 | Channel C: tunnel through `functions.yandexcloud.net` (whitelist-resident); Channel B: tunnel through `telemost.yandex.ru` SFU (whitelist-resident) |
| Whitelist-mode L3 default-drop on ZOV IP | L3 | Both B and C: client → whitelist endpoint; whitelist endpoint speaks ordinary outbound to ZOV (NL→outbound from RU whitelist endpoints is unrestricted) |
| YC ToS ban (proxy/VPN forbidden) | Operational | Channel C: low-volume per account, multi-account pool, innocuous function name, JWT auth gate, rate limits |
| Telemost room hijack / abuse | Operational | Channel B: ephemeral room codes signed with same JWT, single-tenant per session |
| MSK plaintext exposure | Operational / legal | Unchanged from v1 spec — accepted residual risk; entry holds plaintext briefly for routing. Documented in user T&Cs. |
| Cross-border GB charges (May 1) | UX / cost | Aggressive `geoip:ru` + `geosite:category-ru` direct-egress at MSK; client-side warning UI showing month-to-date foreign GB |

## Topology

```
                                     ┌──────────────────────────┐
                                     │  Marzban (on ZOV, mesh)  │
                                     │  users + quota + JWT     │
                                     └────────┬─────────────────┘
                                              │ subscription URI bundle
                                              ▼
                       ┌──────────────────────────────────────────────┐
                       │             RU Client (companion)            │
                       │  picks live channel, exposes local SOCKS5    │
                       └─────┬──────────────────┬────────────────┬────┘
                             │                  │                │
              Channel A      │   Channel C      │   Channel B    │
              VLESS+Reality  │   YC Function    │   olcRTC       │
                +XHTTP       │   HTTP tunnel    │   WebRTC       │
                             │                  │                │
                             ▼                  ▼                ▼
            ┌────────────────────────┐  ┌──────────────┐  ┌───────────────────┐
            │  MaskanyaHopMsk (RU)   │  │  YC Function │  │  Yandex Telemost  │
            │  Reality + XHTTP :443  │  │  yandexcloud │  │  SFU              │
            │  82.146.35.191         │  │  whitelisted │  │  whitelisted      │
            │  geoip:ru → direct     │  │              │  │                   │
            └────────┬───────────────┘  └──────┬───────┘  └─────────┬─────────┘
                     │ Reality outbound        │ HTTPS to ZOV       │ DataChannel
                     │ TCP/8443 (public)       │ (NL public IP)     │ (peer ↔ peer)
                     ▼                         ▼                    ▼
                                ┌──────────────────────────────────┐
                                │   ZenithOfVastness (NL exit)     │
                                │   Reality :8443  (Channel A in)  │
                                │   nginx /yc-bridge (Channel C)   │
                                │   olcRTC bridge daemon (Ch. B)   │
                                │   103.137.249.134                │
                                └────────┬─────────────────────────┘
                                         ▼
                                      Internet
```

The AmneziaWG control mesh (`awg1` on UDP/51821, hub `10.77.0.1` on ZOV, spoke `10.77.0.10` on MSK) is preserved as-is for stats scraping, panel access, and inter-host RPC. **No user traffic flows over AWG** — Channel A's `MSK→ZOV` leg uses Reality over the public internet, exactly as in v1.

## Channel A — VLESS+Reality+XHTTP (primary)

### Purpose
Day-to-day high-throughput channel. Used >95% of the time when no whitelist-mode event is active. Survives the L7 DPI bar of May 2026 if configured correctly.

### Failure modes covered
- TLS-fingerprint detection — fixed by uTLS chrome.
- Active probe to fake decoy — fixed by Reality `dest:` pointing at a real, whitelist-resident server.
- Behavioral classifier — mitigated by XHTTP wrapper.
- L7 SNI blacklist — mitigated by Yandex CDN SNI.

### Failure modes NOT covered
- Whitelist-mode L3 drop on MSK IP — fall through to Channel C.
- Whitelist-mode L3 drop on ZOV IP — Channel A is dead either way (MSK→ZOV outbound also blocked); fall through to Channels B/C, both of which terminate at Yandex-side and bridge to ZOV via NL→YC public connectivity (not subject to the same RU L3 rules).

### Topology
```
Client → MSK :443 (Reality+XHTTP+Vision) → MSK split-router
                                              ├── geoip:ru → freedom out (direct, RU traffic)
                                              └── default → Reality outbound to ZOV :8443 → ZOV freedom out
```

### Inbound spec — `MaskanyaHopMsk` :443

```jsonc
{
  "tag": "reality-xhttp-in",
  "listen": "0.0.0.0",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "<uuid>", "flow": "xtls-rprx-vision", "email": "user@maskanya" }],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "/<per-user-random>",
      "mode": "stream-one",          // stream-one is the only XHTTP mode compatible with xtls-rprx-vision
      "xPaddingBytes": "100-1000"
    },
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "storage.yandex.net:443",   // real Yandex CDN, whitelist-resident, certs are real Yandex
      "xver": 0,
      "serverNames": ["storage.yandex.net"],
      "privateKey": "<reality_private_key_local>",
      "shortIds": ["<per-user-short-id>"],
      "fingerprint": "chrome"             // uTLS — mandatory under May 2026 DPI
    }
  }
}
```

Notes:
- `mode: "stream-one"` keeps Vision compatibility (single bidirectional XHTTP stream). It's the only XHTTP mode that works with `xtls-rprx-vision`; if we ever drop Vision client-side we'd switch to `mode: "auto"`.
- `dest` points at real `storage.yandex.net`, not a co-located fake. This relies on outbound from MSK→storage.yandex.net being unrestricted (it is — Yandex CDN is whitelist-resident and routinely reachable from any RU host). Probes get authentic Yandex TLS responses.
- `serverNames` is a single-element array because we want every probe and every real client to use the same SNI; Reality's per-user discriminator is `shortIds`, not SNI.
- `shortIds` becomes per-user (each Marzban user gets a unique 8-hex short ID). This lets us revoke individual users without rotating server keys.
- We retire the static `reality_decoy_pool` from v1 (`samsung.com`, `lovelive-anime.jp`, etc.). They're not whitelist-resident and they're not what the 2026 playbook recommends.

### Outbound spec — `MaskanyaHopMsk` → `ZenithOfVastness` :8443

Reality outbound from MSK to ZOV: same XHTTP+Reality stack but no Vision (Vision is client-only optimization), and the SNI/decoy is a foreign whitelist-edge service — Cloudflare or Microsoft works since this leg is outside RU DPI's typical reach in normal regime.

```jsonc
{
  "tag": "exit-nl1",
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "103.137.249.134",
      "port": 8443,
      "users": [{ "id": "<chain_uuid>", "encryption": "none", "flow": "" }]
    }]
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "/api/v1/<random-per-chain>",
      "mode": "auto",
      "xPaddingBytes": "100-1000"
    },
    "security": "reality",
    "realitySettings": {
      "show": false,
      "serverName": "www.cloudflare.com",
      "publicKey": "<zov_reality_public_key>",
      "shortId": "<zov_short_id>",
      "fingerprint": "chrome",
      "spiderX": ""
    }
  }
}
```

### Inbound spec — `ZenithOfVastness` :8443

Mirror of MSK :443 but bound to 8443 (ZOV's :443 is taken by 13 production vhosts and remains untouched per the preservation contract). SNI is `www.cloudflare.com`; `dest` is `www.cloudflare.com:443`.

### Split routing on MSK (unchanged from v1, tightened)

```
geoip:ru                      → freedom (direct)
geosite:category-ru           → freedom (direct)
geosite:yandex                → freedom (direct)   ← NEW: keep .ya[ndex].* domestic
geosite:vk                    → freedom (direct)   ← NEW: same for VK
default                       → exit-nl1
```

The two NEW rules are critical for the May 1 cross-border charge issue. Yandex/VK content traffic stays domestic; only foreign-destined traffic crosses the border.

### Client URI (subscription)

```
vless://<uuid>@82.146.35.191:443
  ?type=xhttp
  &mode=stream-one
  &path=%2F<random>
  &security=reality
  &pbk=<msk_reality_public_key>
  &sid=<per-user-short-id>
  &sni=storage.yandex.net
  &fp=chrome
  &flow=xtls-rprx-vision
#Maskanya-A-msk-nl
```

## Channel C — Yandex Cloud Functions HTTP tunnel

### Purpose
Whitelist-mode survival channel with usable throughput (~5–20 Mbps practical, latency-dependent). Activates when Channel A fails — typically because MSK IP got dropped at L3 in a regional whitelist event.

### How it survives whitelist mode
The endpoint client connects to is `https://functions.yandexcloud.net/d4eXXXXXXX...` — that hostname resolves to Yandex's universally-whitelisted CDN. RKN cannot drop those CIDRs without breaking Yandex services for all RU users; it does not. So the client's outbound HTTPS request reaches the function regardless of whitelist mode. The function then makes its own outbound to ZOV (NL); RU egress from a YC-resident IP is permitted.

### Components

**Frontend:** YC serverless function, language Node.js 20, exposes `POST /tunnel`.
- Auth: `Authorization: Bearer <jwt>`. JWT issued by Marzban, signed with HS256, claims: `sub` (user UUID), `exp` (1h), `quota_gb_remaining` (read-only).
- Request body: `{ "method": "CONNECT", "host": "<upstream>", "port": <port>, "data": "<base64 chunk>" }` for stateless chunk mode, or upgrade to WebSocket for streaming mode.
- Function opens a TCP connection to ZOV's bridge endpoint (`bridge.maskanya.animeenigma.ru:443`) and forwards. ZOV's nginx terminates TLS, validates a function-only cert pin, and proxies to the local `xray_yc_bridge` inbound.
- On every invocation: increments user's GB counter via the Marzban API; refuses if quota exhausted.

**Upstream on ZOV:** new xray inbound `xray_yc_bridge`, protocol VLESS over WebSocket, listening on `127.0.0.1:8444` (mesh-internal), fronted by nginx vhost `bridge.maskanya.animeenigma.ru` on `:443` (added to ZOV's existing nginx). nginx terminates TLS with an LE cert (HTTP-01 via existing certbot pattern). Only Yandex outbound IPs allowed via `allow ...; deny all;`.

```nginx
server {
    listen 443 ssl http2;
    server_name bridge.maskanya.animeenigma.ru;
    ssl_certificate /etc/letsencrypt/live/bridge.maskanya.animeenigma.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/bridge.maskanya.animeenigma.ru/privkey.pem;

    # YC Functions egress IP ranges (kept current via ansible cron task)
    include /etc/nginx/maskanya/yc_egress_allow.conf;
    deny all;

    location /yc-tunnel {
        proxy_pass http://127.0.0.1:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### Deployment
- Function source code: `infra/yc-functions/tunnel/` (TypeScript, ~200 LOC, bundled with esbuild).
- Deployment driver: `infra/yc-functions/Makefile` + Terraform (`yandex` provider). Operator runs `make yc-deploy` from a YC CLI-authenticated shell.
- Function name: `image-thumbnailer-v2` (deliberately innocuous — YC ToS blanks proxy/VPN deployments).
- Service account: dedicated SA with **only** `serverless.functions.invoker` role, no broader privilege.
- Multi-account strategy: support 2–3 parallel YC tenancies per operator. Each tenancy is one deployment of the same function, independent JWT key, and one row in `secrets/yc_endpoints.yml`. If one gets ToS-banned, others stay live; subscription serves all live ones.

### Failure modes
- ToS ban → rotate to next account (subscription auto-failover ignores the dead URI).
- Free-tier exhaustion (1M invocations / 10 GB-s / month) → graceful degradation: function returns 429, client falls back to Channel B. Paid bursting available at ~₽1/GB; budget alarm at 80% of monthly cap.
- Function cold-start latency (~300 ms first request after idle) → kept hot by 1-min ping from ZOV.

### Throughput envelope
Practical: 5–20 Mbps per session. Free tier supports ~40–60 hours of light browsing per user/month; ~3 hours of HD video. Streaming is not the use case for Channel C; it's "I need to check email and slack while in whitelist-mode" survival.

### Client URI

Custom URI scheme handled by the companion app:
```
maskanya-yc://<bearer-jwt>@<function-url>?fp=https&kt=<key-tag>#Maskanya-C-yc1
```

## Channel B — olcRTC (WebRTC over Yandex Telemost)

### Purpose
Last-resort whitelist-mode channel. Slowest of the three; works when both A and C are degraded (Channel A blocked at L3, Channel C function quota burned or all YC accounts banned).

### How it survives
Yandex Telemost's SFU sits at `*.telemost.yandex.net` — universally whitelisted, never blocked. WebRTC ICE/DTLS/SCTP flows ride on top of TURN relays inside Yandex's whitelist-resident CIDRs. The client's traffic is genuinely Telemost call traffic from RKN's view; it isn't pretending. The peer-to-peer DataChannel inside that call is what we use.

### Components

**Bridge daemon on ZOV:** Go binary using [pion/webrtc](https://github.com/pion/webrtc).
- Boots, authenticates to Yandex Telemost (anonymous join via room link, no Yandex account required for joining a public/unlisted room),
- Joins a pre-arranged room (link signed via JWT shared with the client through Marzban subscription),
- Accepts a WebRTC peer connection from the client peer in the same room,
- Bridges DataChannel ↔ local TCP socket → forwards to ZOV's `xray_yc_bridge` inbound (same upstream endpoint Channel C uses; reused for code path consolidation),
- Deployed under systemd as `maskanya-olcrtc-bridge.service`, restart=always.

**Client:** companion app (see "Companion app" below) with embedded WebRTC stack and Telemost room joiner. Establishes the call, opens DataChannel, exposes local SOCKS5 to v2rayN/system proxy.

### Constraints
- DataChannel max message: 16 KiB (RFC 8831), practical SCTP limit ~64 KiB chunked. Large transfers chunked + reassembled.
- Practical throughput: 0.5–2 Mbps per call (limited by SFU-relay overhead and WebRTC congestion control).
- Connection setup latency: 2–5 seconds (ICE gathering, DTLS handshake, room join).
- Idle timeout: Telemost rooms get evicted after N minutes of silence — bridge keeps a synthetic keepalive flow.

### olcRTC project status
The article (`habr.com/ru/articles/1027276`) marks olcRTC as pre-alpha. We treat it as Phase 4 implementation; the spec defines the integration shape (where the bridge runs, what protocol the DataChannel carries, who supplies room codes), and we accept that the actual bridge daemon may not be production-ready before late summer 2026. Until then, Channel B is documented but disabled in subscriptions.

### Client URI

```
maskanya-rtc://<bearer-jwt>@telemost.yandex.ru/<room-code-signed>#Maskanya-B-rtc1
```

## Companion app (Channel B/C client)

v2rayN, Hiddify, Streisand and friends speak only Channel A. To use B and C we need a small custom client. Scope:

- Cross-platform desktop (Tauri or Electron — TBD; Tauri preferred for binary size).
- Reads the Maskanya subscription URL, parses all three URI schemes.
- Pings each channel periodically; picks the fastest live one.
- Exposes a system SOCKS5 / TUN proxy on `127.0.0.1:1080` (libxray and gVisor-tun bundled).
- Speaks XHTTP+Reality (Channel A) via embedded xray-core.
- Speaks `maskanya-yc://` via plain HTTPS + JWT.
- Speaks `maskanya-rtc://` via embedded pion-webrtc.
- Updates over GitHub Releases (whitelist-mode caveat: GitHub is partially blocked from RU; first install must happen out-of-regime; updates fetched via Channel C while running).

The companion is an explicit Phase 3 deliverable in this spec (see Roadmap below).

## Marzban as single source of truth

Existing Marzban deployment on ZOV (`panel.maskanya.animeenigma.ru`) keeps owning users, plans, and quota. We extend it with:

- A custom subscription template that emits **all three URIs** per user (and only the active ones, hiding ToS-banned YC accounts and disabled-Phase-4 olcRTC).
- A JWT signing endpoint (`POST /api/jwt`) — issues short-lived JWTs to channels B and C. Reuses the user's API token for auth.
- Per-user `shortIds` (Channel A) provisioned automatically on user creation.
- Quota hooks: Channel C reports per-invocation GB to Marzban via the same `/api/usage` Marzban already exposes; Channel A continues to use xray's stats API as today.

## Subscription URI bundle (sample)

```
# Maskanya — bundle for user@maskanya
vless://...                                          # Channel A — primary
maskanya-yc://...@functions.yandexcloud.net/d4eXX..  # Channel C — YC tunnel #1
maskanya-yc://...@functions.yandexcloud.net/d4eYY..  # Channel C — YC tunnel #2 (failover account)
maskanya-rtc://...@telemost.yandex.ru/abc123         # Channel B — disabled until Phase 4
```

The companion sorts by RTT, attempts in order, falls back on failure.

## Cross-cutting infrastructure

### Secrets (unchanged shape, new keys)

`secrets/xray_clients.yml` (SOPS+age) — adds:
- `users[].short_id` — per-user 8-hex Reality discriminator (Channel A).
- `jwt_signing_key` — Marzban's HS256 secret for B/C JWTs.
- `yc_endpoints[]` — list of `{name, function_url, key_tag, status}` for Channel C.
- `olcrtc.room_seed` — secret used to derive Telemost room codes for Channel B.

### Ansible roles (delta from v1)

| Role | Status | Change |
|---|---|---|
| `common` | unchanged | — |
| `firewall` | unchanged | preserves additive iptables on ZOV; nftables on MSK as before |
| `amneziawg` | unchanged | mesh stays as control plane only |
| `node_exporter` | unchanged | — |
| `xray_common` | minor | bump xray-core minimum to v25.4.x (XHTTP+stream-one available); reality_keygen unchanged |
| `xray_entry` | rewrite | new template: XHTTP+Reality+Vision inbound on :443; outbound also XHTTP+Reality; per-user shortIds; `dest: storage.yandex.net:443`; chrome fp |
| `xray_exit` | rewrite | mirror of entry-side, SNI=cloudflare.com; adds parallel `xray_yc_bridge` inbound on `127.0.0.1:8444` |
| `nginx_yc_bridge` | NEW | adds `bridge.maskanya.animeenigma.ru` vhost to ZOV's existing nginx; LE cert via existing certbot; YC egress allowlist |
| `marzban_panel` | extension | new subscription template + JWT endpoint |
| `olcrtc_bridge` | NEW (Phase 4) | systemd unit + Go binary (`/usr/local/bin/maskanya-olcrtc`); deployed but disabled by default |
| `yc_egress_refresh` | NEW | weekly cron job that fetches YC's published egress CIDRs and rewrites `/etc/nginx/maskanya/yc_egress_allow.conf` |

### Out-of-tree deployment (`infra/yc-functions/`)

Outside Ansible:
- Terraform module `infra/yc-functions/main.tf` — provisions the function, IAM, trigger, log shipping.
- Function source `infra/yc-functions/tunnel/src/`.
- `Makefile` targets: `yc-deploy`, `yc-rotate`, `yc-status`.
- Operator-driven, not part of `make apply`. State stored in `infra/yc-functions/.tfstate.encrypted` (SOPS).

### Monitoring (unchanged shape, new sources)

Existing Prometheus on ZOV scrapes `node_exporter` over the AWG mesh. Add:
- xray-core stats from MSK (already scheduled in v1 Phase 2).
- `bridge.maskanya.animeenigma.ru` access log → Loki → counts per-user GB on Channel C.
- `maskanya-olcrtc-bridge.service` exposes `:9101` Prometheus endpoint when running.
- Grafana dashboard `Maskanya / Channels` with three panels: A throughput, C invocations + GB, B active sessions.

### Live-host preservation (unchanged)

The ZOV preservation contract from the v1 spec is unchanged and remains binding:

- 13 production nginx vhosts on :80/:443 — untouched
- 20+ Docker containers — untouched
- Existing `awg0` mesh on UDP/51820 — untouched
- existing certbot + LE certs — used for new `bridge.maskanya...` vhost (additive)
- fail2ban + timesyncd — untouched
- `preserve_*: true` flags in `host_vars/ZenithOfVastness.yml` continue to gate every new role

The new `nginx_yc_bridge` role adds a vhost; it does not replace nginx. The `olcrtc_bridge` role adds a binary + unit; it does not modify network state.

MSK preservation is irrelevant (dedicated host, post-wipe baseline).

## Cost envelope

| Item | Cost | Notes |
|---|---|---|
| MaskanyaHopMsk (FirstVDS) | ~₽300/mo | unchanged |
| ZenithOfVastness (NL, shared) | $0 marginal | shared host, infra cost not attributed |
| YC Functions (Channel C) | $0 free / ~$2/mo paid | per-account; we run 2–3 accounts |
| YC outbound (function → ZOV) | ~₽1/GB | counts against function's egress budget; capped per user |
| Telemost (Channel B) | $0 | free service; uses anonymous join |
| Marzban changes | dev time only | hosted on existing ZOV |
| Companion app | dev time only | hosted on GitHub Releases (free) |

Per-user channel-C cost projection at 50 users × 5 GB/mo on YC ≈ ₽250/mo total. Trivial.

## Roadmap / phasing

**Phase 1 — VLESS-2026 hardening (Week 1, ~3–5 days):**
Land `xray_entry` and `xray_exit` rewrites with chrome fingerprint + XHTTP+stream-one+Vision + Yandex CDN SNI + per-user shortIds. Rotate Reality keys. Update Marzban subscription template to emit the new Channel A URI. No new components.

**Phase 2 — YC bridge upstream on ZOV (Week 2, ~3 days):**
Add `xray_yc_bridge` inbound on ZOV. Add `nginx_yc_bridge` role with `bridge.maskanya.animeenigma.ru` vhost + LE cert + YC egress allowlist. Verify upstream is reachable from a manual `curl` test from a YC sandbox.

**Phase 3 — Channel C end-to-end + companion v0 (Weeks 3–5, ~10 days):**
Implement YC Function (TypeScript). Terraform deployment. Operator deploys 2 production accounts. Build companion app v0 (Tauri, Channel A + Channel C only — no Channel B yet). JWT issuance from Marzban. End-to-end: companion → Function → bridge → ZOV → internet.

**Phase 4 — olcRTC (Weeks 6+, deferred):**
Build `olcrtc_bridge` daemon (Go + pion). Embed WebRTC in companion app. Wire room-code exchange via Marzban subscription. Treat as exploratory; may slip without blocking Phases 1–3.

**Phase 5 — Channel selection & hardening (after Phase 3):**
Auto-failover in companion. Per-channel health probing. User-facing channel UI with "you're on Channel A / C / B". Per-channel stats in panel.

## Migration plan from current state

Current state: v1 deployed on ZOV with Reality+Vision+TCP+plain SNI; MSK was reset and is awaiting re-bootstrap (per memory `project_zov_bootstrap_state.md` 2026-04-18).

Steps:

1. Land Phase 1 changes (xray template rewrites) on ZOV first while MSK is still down — re-converge ZOV's exit role with new template; keep `xray_inbound_port: 8443` and SNI = `www.cloudflare.com`. Verify via `xray-maskanya -test` and a manual client connection from the operator's laptop.
2. Re-bootstrap MSK (existing playbook + outstanding fixes from `project_zov_bootstrap_state.md`). Apply Phase 1 entry template. Verify chain `msk-nl` is live.
3. Cut over the operator's own subscription URI to the new Channel A. Use Maskanya for a week. If stable, mark Phase 1 complete.
4. Phases 2–4 land additively; v1 Channel A keeps serving traffic the entire time.

Old v1 client subscription URIs (samsung.com SNI, no XHTTP) become invalid after Step 3 — every existing user (operator only at this point) gets a fresh URI.

## Open questions

1. **YC account strategy.** Is the operator OK creating 2–3 separate Yandex tenancies under separate emails to absorb ToS bans? Each is ~30 min of manual setup. Alternative: only one account, accept that a ban kills Channel C until next setup.
2. **Companion app distribution.** First install happens before Maskanya is active, so it must be reachable from RU without a VPN. Options: (a) GitHub Releases (intermittent from RU); (b) Telegram bot serving installers; (c) Yandex.Disk public link (trivially whitelist-resident); (d) all three with mirroring. Default plan: (c) primary, (a) mirror.
3. **olcRTC anonymous join.** Does Telemost actually allow joining a room without a Yandex account? Recent Telemost (April 2026) requires login for hosting, but joining is sometimes anonymous. Needs empirical verification before Phase 4 commits to "no Yandex account on bridge".
4. **JWT lifetime.** 1 hour means companion must refresh hourly. If companion is offline (Channel A not working AND companion can't reach Marzban for refresh), B/C are dead. Solution: fetch a 24h-expiry JWT during normal operation, hand to B/C; B/C still revalidate against Marzban on each session start. Revisit during Phase 3.
5. **MSK plaintext.** Same residual risk as v1: MSK holds plaintext briefly while routing. New spec doesn't fix it. Consider whether we should add a user-facing explainer in the panel.
6. **xray-core version.** XHTTP-mode-stream-one + Vision requires xray-core v25.x (newer than the v1.8.24 currently pinned). Need to bump and re-verify; new version may require Marzban update too.

## Sources

- Habr 1009542 — TSPU 2026 detection model + XHTTP recommendation
- Habr 1027276 — whitelist-mode L3+L7 architecture, 6 working bypass methods including olcRTC and YC Functions
- Habr 1027990 — operator's year-long evolution; running real local web server alongside masking
- Habr 1021160 — 4-layer survival architecture (VLESS / Cloudflare / YC / Telemost)
- Habr 992240 — RPRX directive on bare VLESS in 2026
- Habr 1017492 — May 1 cross-border traffic charges
