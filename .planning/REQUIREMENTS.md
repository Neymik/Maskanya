# Requirements: Maskanya

**Defined:** 2026-05-08
**Core Value:** A Russian user can browse the open internet reliably even during a whitelist-mode regional event.

## v0.1 Requirements (Three-Channel MVP)

Requirements for the first shippable release. Each maps to a milestone phase.

### Validation (VAL)

Empirical gates before architectural commitments.

- [ ] **VAL-01**: VLESS+Reality+XHTTP-stream-one+Vision+chrome-uTLS+Yandex-CDN-SNI on `:443` from MSK passes current RU DPI — `curl ifconfig.me` through tunnel returns `82.146.35.191` from a RU client AND sustains 5+ minutes of mixed browsing without disconnect.
- [ ] **VAL-02**: WebRTC `RTCPeerConnection` + `DataChannel` reaches `open` state in a Russian browser, with bytes flowing both ways between two peers.
- [ ] **VAL-03**: `https://functions.yandexcloud.net/<id>` is reachable from a RU client, AND a deployed function can `fetch()` foreign URLs (e.g. `ifconfig.me` returns a YC-resident IP).

### Channel A — VLESS hardened (CHA)

The primary high-throughput path.

- [ ] **CHA-01**: ZOV's `:443` is shared via `nginx_stream` SNI demuxer — production 13 vhosts and Maskanya xray Reality coexist without disruption to either.
- [ ] **CHA-02**: MSK runs xray with Reality+XHTTP-stream-one+Vision+chrome-uTLS, SNI=`storage.yandex.net`, listening on `:443`.
- [ ] **CHA-03**: ZOV runs xray with Reality+XHTTP+chrome-uTLS, SNI=`www.cloudflare.com`, listening on `127.0.0.1:8443` (behind nginx demuxer).
- [ ] **CHA-04**: MSK→ZOV outbound terminates on ZOV `:443` (via nginx demuxer routing SNI=`www.cloudflare.com` to xray), NOT on `:8443` directly.
- [ ] **CHA-05**: Each Marzban user gets a unique 8-hex Reality `shortId` so user revocation does not require full server-key rotation.
- [ ] **CHA-06**: Split routing on MSK keeps `geoip:ru`, `geosite:category-ru`, `geosite:yandex`, `geosite:vk` traffic egressing direct from MSK (not crossing the May-1 cross-border GB charge boundary).

### Channel C — Yandex Cloud Functions tunnel (CHC)

Whitelist-mode survival channel with usable throughput.

- [ ] **CHC-01**: A YC Function written in TypeScript/Node.js 20 is deployed to a separate "innocuous-named" YC tenancy via Terraform. Function name not revealing of proxy/VPN nature.
- [ ] **CHC-02**: Function performs HTTP CONNECT to `bridge.maskanya.animeenigma.ru:443` (not `:8443`) on ZOV; nginx SNI demuxer routes the TLS to the `xray_yc_bridge` inbound on `127.0.0.1:8444`.
- [ ] **CHC-03**: Function authenticates each request with a JWT issued by Marzban (HS256, 1-hour expiry) before forwarding.
- [ ] **CHC-04**: ZOV's nginx allowlists only YC egress CIDRs for the `bridge.*` server (uses proxy-protocol passed real IPs from the stream demuxer).
- [ ] **CHC-05**: Operator can run two parallel YC tenancies; if one is ToS-banned, the other keeps Channel C live; subscription auto-omits dead URIs.

### Subscriptions and clients (SUB)

User-facing delivery.

- [ ] **SUB-01**: Marzban subscription URL (`sub.maskanya.animeenigma.ru/<token>`) emits all three URIs in a single response: `vless://...` (Channel A), `maskanya-yc://...` (Channel C), `maskanya-rtc://...` (Channel B placeholder).
- [ ] **SUB-02**: A desktop companion app (Tauri, OS-X+Windows+Linux) parses the bundle, exposes a local SOCKS5 on `127.0.0.1:1080`, and routes through the first reachable channel (manual selection in v0.1; auto-failover deferred to v0.2).
- [ ] **SUB-03**: Companion app's first install reachable from RU without an existing VPN (distributed via Yandex.Disk public link mirrored on GitHub Releases).
- [ ] **SUB-04**: Revoking a user in Marzban kills their access on **all three** channels (Channel A via xray API, Channel C via JWT issuance freeze, Channel B via room-code revocation — the last is no-op until Phase 4).

### Operations (OPS)

Cross-cutting hygiene.

- [ ] **OPS-01**: All secrets (Reality private keys, JWT signing key, YC service-account credentials, Telemost room seed) stored SOPS+age-encrypted under `secrets/`; never committed plaintext.
- [ ] **OPS-02**: Prometheus on ZOV scrapes xray stats from MSK over the AWG mesh; Grafana dashboard `Maskanya / Channels` shows A throughput, C invocations + GB, B sessions.
- [ ] **OPS-03**: nginx demuxer cutover on ZOV is reversible — operator can roll back to direct `listen 443` on the production vhosts within 1 minute via a single Ansible flag.

## v0.2 Requirements (Future)

Deferred to next milestone.

### olcRTC (RTC)

- **RTC-01**: A Pion-based WebRTC bridge daemon runs on ZOV, joins a Yandex Telemost room, and brokers DataChannel↔TCP traffic to `xray_yc_bridge`.
- **RTC-02**: Companion app embeds the WebRTC stack and joins the same room as the bridge to establish `maskanya-rtc://` sessions.
- **RTC-03**: Telemost rooms rotate per-session via JWT-signed room codes.

### Auto-failover (FAIL)

- **FAIL-01**: Companion app probes all three channels on connect, picks the lowest-RTT live one.
- **FAIL-02**: On mid-session failure, companion silently switches to the next live channel without user action.

### Multi-region exit (MR)

- **MR-01**: `MaskanyaExitKZ1` activates as a second exit; users see chain options `msk-nl` and `msk-kz` in subscription.
- **MR-02**: Per-chain client URI emission in subscription template.

## Out of Scope (v0.1)

| Feature | Reason |
|---------|--------|
| Public registration / paid SaaS billing | Invite-only beta — payments architecture is separate milestone |
| Mobile-native client | Desktop suffices for invite-only; mobile users use v2rayN-equivalents on Channel A only |
| `.com`/non-`.ru` domain migration | Spec acknowledges `.ru` TLD risk; deferred until invite-only ends |
| Smart chain recommendations | Single chain (msk-nl) until KZ exit lands |
| Monitoring of olcRTC bridge | Bridge isn't built in v0.1; nothing to monitor |
| Move `xray-maskanya` (production v1) configs into v0.1 stack | v1 was VLESS+Reality+Vision+TCP on `:8443` — completely superseded; removed during Phase 1 cutover, not migrated |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| VAL-01 | Phase 0 | Pending |
| VAL-02 | Phase 0 | Pending |
| VAL-03 | Phase 0 | Pending |
| CHA-01 | Phase 1 | Pending |
| CHA-02 | Phase 1 | Pending |
| CHA-03 | Phase 1 | Pending |
| CHA-04 | Phase 1 | Pending |
| CHA-05 | Phase 1 | Pending |
| CHA-06 | Phase 1 | Pending |
| CHC-01 | Phase 3 | Pending |
| CHC-02 | Phase 2 | Pending |
| CHC-03 | Phase 3 | Pending |
| CHC-04 | Phase 2 | Pending |
| CHC-05 | Phase 3 | Pending |
| SUB-01 | Phase 3 | Pending |
| SUB-02 | Phase 3 | Pending |
| SUB-03 | Phase 3 | Pending |
| SUB-04 | Phase 3 | Pending |
| OPS-01 | Phase 1 | Pending |
| OPS-02 | Phase 1 | Pending |
| OPS-03 | Phase 1 | Pending |

**Coverage:**
- v0.1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-05-08*
*Last updated: 2026-05-08 after milestone v0.1 scope lock-in*
