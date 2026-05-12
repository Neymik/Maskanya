# Roadmap: Maskanya v0.1 Three-Channel MVP

## Overview

Validate the three-channel architecture works against the May 2026 RU regulatory regime, then build out each channel atop the existing two-host infrastructure (`ZenithOfVastness` NL exit + `MaskanyaHopMsk` Moscow entry). Phase 0 is a hard gate — its empirical result determines whether the rest of the roadmap proceeds as designed (PASS) or pivots to a Channel-C-first variant (FAIL on Channel A).

Underlying design spec: [`docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md`](../docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md).

## Phases

**Phase Numbering:**
- Integer phases (0, 1, 2, 3): planned milestone work
- Decimal phases (1.1, etc.): urgent insertions (marked INSERTED), not yet present

- [ ] **Phase 0: PoC validation** — empirical answer to "does Channel A's protocol stack pass current RU DPI"
- [ ] **Phase 1: Channel A hardening + nginx SNI demuxer** — production VLESS path with port-discipline-correct architecture
- [ ] **Phase 2: ZOV bridge upstream** — `xray_yc_bridge` inbound + `bridge.maskanya.*` vhost behind the demuxer
- [ ] **Phase 3: YC Function frontend + companion app + Marzban subscription** — Channel C end-to-end + delivery to users
- [ ] **Phase 4: Channel B olcRTC** — operator-tested WebRTC-over-wbstream tunnel; v0 manual deploy PASS (4.7 Mbps sustained from JST, 0 errors / 0 disconnects over 5 min), then Ansible + companion-app integration

## Phase Details

### Phase 0: PoC validation

**Goal**: Determine whether the May-2026-hardened VLESS+Reality+XHTTP+chrome+Yandex-SNI stack on `:443` passes current RU DPI when running on `MaskanyaHopMsk`. Output: a recorded PASS/PARTIAL/FAIL with diagnostic artifacts; no production-ready code, just a binary go/no-go signal.

**Depends on**: Nothing. First phase.

**Requirements**: VAL-01, VAL-02, VAL-03

**Success Criteria** (what must be TRUE):
  1. A Russian client running v2rayN/NekoRay with the PoC VLESS URI gets `82.146.35.191` from `curl ifconfig.me` AND sustains 5+ minutes of mixed browsing without disconnect (VAL-01).
  2. The `experiments/b-webrtc/manual-test.html` page in a Russian browser establishes a DataChannel between two tabs and round-trips text messages (VAL-02).
  3. A YC Function deployed to a fresh tenancy is reachable from a RU client AND its `fetch('https://ifconfig.me')` returns a YC-resident IP from the function's response body (VAL-03).
  4. `experiments/a-vless/RESULTS.md` exists with verdict, tested-config snapshot, and recommendation written by the operator after the test session.

**Plans**: 1 plan

Plans:
- [ ] 00-01: Deploy single-hop xray-poc to MSK; run operator-side smoke test; run RU empirical test; failure-mode triage if needed; record results

### Phase 1: Channel A hardening + nginx SNI demuxer

**Goal**: Cut over ZOV's `:443` from "13 production vhosts directly bound" to "nginx_stream SNI-demuxer in front, demuxing to xray Reality + bridge.* + production vhosts on `127.0.0.1:8000`" without disrupting any production vhost. Then redeploy MSK xray and ZOV xray with the May-2026-hardened config (chrome uTLS, Yandex CDN SNI, per-user shortIds). End state: Channel A is production-ready on `:443` end-to-end.

**Depends on**: Phase 0 PASS or PARTIAL. (FAIL → skip Phase 1; rework as Channel-C-first.)

**Requirements**: CHA-01, CHA-02, CHA-03, CHA-04, CHA-05, CHA-06, OPS-01, OPS-02, OPS-03

**Success Criteria** (what must be TRUE):
  1. All 13 production nginx vhosts respond identically before and after the demuxer cutover (verified via HTTP HEAD diff on each vhost).
  2. ZOV xray-maskanya rebinds to `127.0.0.1:8443`; public `:8443` is closed; nginx demuxer routes SNI=`www.cloudflare.com` to it.
  3. MSK xray on `:443` accepts client URIs emitted by Marzban subscription, with each user using a distinct shortId.
  4. Split-routing rules at MSK keep `geoip:ru` and `geosite:yandex|vk|category-ru` traffic egressing direct from MSK; verified by traffic flow test (RU domain via VPN ≠ exit through ZOV).
  5. Single Ansible flag (`maskanya_nginx_demux_enabled: false`) reverts the cutover within 1 minute (OPS-03).
  6. Prometheus scrapes xray stats from MSK over AWG mesh; Grafana dashboard renders Channel A throughput.

**Plans**: 4 plans

Plans:
- [ ] 01-01: `nginx_sni_demux` Ansible role — stream-block + 13-vhost migration to internal port + rollback flag
- [ ] 01-02: `xray_exit` rewrite — Reality+XHTTP+chrome on `127.0.0.1:8443`, replaces v1 production xray-maskanya
- [ ] 01-03: `xray_entry` rewrite + per-user shortIds + tightened split-routing (`yandex`/`vk` direct rules)
- [ ] 01-04: Marzban subscription template update + monitoring wiring (Channel A panel)

### Phase 2: ZOV bridge upstream

**Goal**: Stand up the Channel C upstream on ZOV — `xray_yc_bridge` xray inbound on `127.0.0.1:8444`, fronted by `bridge.maskanya.animeenigma.ru` nginx http-server on `127.0.0.1:8000`, gated by YC-egress-CIDR allowlist via proxy-protocol-passed real IPs from the stream demuxer. End state: ZOV is ready to accept HTTP CONNECT from a YC Function.

**Depends on**: Phase 1 (the SNI demuxer must exist before another tenant lands behind it).

**Requirements**: CHC-02, CHC-04

**Success Criteria** (what must be TRUE):
  1. `curl --resolve bridge.maskanya.animeenigma.ru:443:103.137.249.134 https://bridge.maskanya.animeenigma.ru/yc-tunnel` from a YC sandbox VM returns a valid TLS handshake (returns `xray_yc_bridge`-shaped response — even a 400 is fine; we're verifying reachability).
  2. The same curl from a non-YC IP returns `403 Forbidden` from nginx (allowlist working).
  3. `yc_egress_refresh` Ansible role keeps `/etc/nginx/maskanya/yc_egress_allow.conf` updated weekly with current YC egress CIDRs.
  4. proxy-protocol header from stream demuxer correctly populates `$proxy_protocol_addr` in the http server (verified in nginx access log).

**Plans**: 2 plans

Plans:
- [ ] 02-01: `nginx_yc_bridge` Ansible role — vhost on `127.0.0.1:8000`, LE cert, allowlist include
- [ ] 02-02: `xray_yc_bridge` xray inbound + `yc_egress_refresh` weekly cron

### Phase 3: YC Function frontend + companion app + Marzban subscription

**Goal**: Deploy the YC Function (Channel C frontend), wire JWT issuance into Marzban, build a v0 desktop companion app that consumes the three-URI subscription bundle, and ship subscription delivery via Yandex.Disk + GitHub Releases mirror. End state: Channel A and Channel C are usable end-to-end by an invite-only user; Channel B is a placeholder URI in the bundle.

**Depends on**: Phase 2.

**Requirements**: CHC-01, CHC-03, CHC-05, SUB-01, SUB-02, SUB-03, SUB-04

**Success Criteria** (what must be TRUE):
  1. YC Function deployed to two parallel YC tenancies via Terraform; both endpoints live and authenticated.
  2. JWT issuance endpoint on Marzban returns valid 1-hour-expiry tokens for an authenticated user; the function rejects expired/invalid JWTs with 401.
  3. Companion app v0 (Tauri) parses the subscription bundle, lets user pick channel manually, exposes local SOCKS5; v2rayN can use it as upstream.
  4. End-to-end test: from a RU client via companion → Channel A → ZOV → internet works; switching to Channel C → YC Function → ZOV → internet also works.
  5. Revoking a user in Marzban kills both channels A and C within ≤1 minute (Channel B revocation is no-op stub for v0.1).
  6. Subscription URL reachable from RU without VPN (Yandex.Disk public link tested from RU).

**Plans**: 4 plans

Plans:
- [ ] 03-01: YC Function source + Terraform + multi-tenancy deployment driver
- [ ] 03-02: Marzban JWT issuance endpoint + subscription template emitting 3 URIs
- [ ] 03-03: Companion app v0 (Tauri, manual channel pick, SOCKS5 listener)
- [ ] 03-04: First-install distribution channel (Yandex.Disk + GitHub Releases mirror) + end-to-end revocation test

### Phase 4: Channel B olcRTC

**Goal**: Stand up Channel B (WebRTC tunnel parasitizing Russian whitelisted video-call SFUs) using upstream `openlibrecommunity/olcrtc`. v0 brought forward from the original Phase 4 slot — upstream now ships working binaries, collapsing the original "build a custom pion daemon" scope into "vendor + scp + systemctl". v0 = manual operator-driven; subsequent plans add Ansible, companion-app, and per-user multi-tenancy.

**Depends on**: Nothing strictly — v0 is independent of Phases 1–3. Companion-app integration (04-03) depends on Phase 3 Tauri scaffolding.

**Requirements**: CHB-01-v0 (to be registered in REQUIREMENTS.md as a Phase 4 backlog item).

**Success Criteria**: see `.planning/phases/04-channel-b-olcrtc-v0/04-SPEC.md`. v0 result: PASS — see `experiments/b-webrtc/RESULTS-olcrtc-v0.md`.

**Plans**: 1 delivered (PASS); 4 in backlog

Plans:
- [x] 04-01: v0 manual deploy — vendor upstream, build, scp to ZOV, operator-test (RESULT: PASS — 4.7 Mbps sustained from JST over 5 min, 0 errors, 0 disconnects)
- [ ] 04-02 (backlog): `olcrtc_bridge` Ansible role (bake in AF_NETLINK + single-StateDirectory lessons)
- [ ] 04-03 (backlog): companion-app integration + `maskanya-rtc://` URI emission
- [ ] 04-04 (backlog): Marzban subscription template for Channel B + per-user key derivation
- [ ] 04-05 (backlog): Telemost + SaluteJazz fallback carriers + room rotation

## Progress

**Execution Order:**
Phases execute in numeric order: 0 → 1 → 2 → 3.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. PoC validation | 0/1 | Ready to execute | - |
| 1. Channel A hardening + demuxer | 0/4 | Blocked on Phase 0 | - |
| 2. ZOV bridge upstream | 0/2 | Blocked on Phase 1 | - |
| 3. YC Function + companion + sub | 0/4 | Blocked on Phase 2 | - |
| 4. Channel B olcRTC | 1/5 | v0 PASS (4.7 Mbps sustained from JST) | 04-01: 2026-05-12 |

**Total:** 1/16 plans complete. ~6% milestone progress.

## Rollback story

Each phase is reversible:
- Phase 0: `experiments/a-vless/scripts/teardown.sh` removes everything from MSK in <30s.
- Phase 1: `maskanya_nginx_demux_enabled: false` Ansible flag reverts to the pre-demuxer state in <1min (OPS-03).
- Phase 2: removing the `nginx_yc_bridge` vhost takes one nginx reload; xray_yc_bridge inbound is loopback-only and benign even if left running.
- Phase 3: YC Functions are deleted via `yc serverless function delete`; Marzban subscription template change is one git revert.

---
*Roadmap defined: 2026-05-08*
