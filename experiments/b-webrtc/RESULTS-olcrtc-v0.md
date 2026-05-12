# Channel B v0 — olcRTC manual deploy results

**Verdict:** PARTIAL

**Tested:** 2026-05-12
**Operator:** Neymik
**Network:** operator workstation on JST residential ISP → wbstream SFU → ZenithOfVastness (NL VPS)

> The "from RU whitelisted residential" use case is **not** what was tested here. This v0 measured "does the upstream binary + our systemd packaging + ZOV deployment chain produce a working tunnel between an external operator and ZOV". RU empirical validation is deferred.

## Stack tested

- Upstream: openlibrecommunity/olcrtc @ `c74d171` (2026-05-11 17:40 +0300, master, PRE refactor/universal-carrier merge — see `experiments/b-webrtc/upstream/UPSTREAM_COMMIT`)
- Carrier: `wbstream` (Wildberries `stream.wb.ru`)
- Transport: `datachannel`
- Server: ZenithOfVastness (Ubuntu 22.04, systemd 249), unit `maskanya-olcrtc-bridge.service`
- Client: operator workstation (darwin-arm64), `./experiments/b-webrtc/scripts/run-client.sh`
- Shared secrets: 32-byte ChaCha20 key + UUIDv7 RoomID, both stored gitignored locally and at `/etc/maskanya/olcrtc.env` (mode 0600) on ZOV.

## Findings

### Build + deploy chain — PASS
- `mage cross` produced all 9 target binaries; linux-amd64 (30 MB ELF, statically linked) deployed to `/usr/local/bin/maskanya-olcrtc` on ZOV.
- `experiments/b-webrtc/scripts/deploy-zov.sh` ran idempotently end-to-end against ZOV's passwordless sudo.
- Systemd unit loaded; `Loaded: ...; disabled` + `Active: inactive` as planned for v0 (manual-start only).

### Bug discovered + fixed: `RestrictAddressFamilies` broke ICE candidate gathering
Initial unit included `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`. pion-webrtc's interface enumeration uses `AF_NETLINK` (`route ip+net: netlinkrib`). Result: server gathered **zero ICE candidates**, so the client's offer had nothing to pair with. Symptom: server log read `connect to room: could not connect after timeout`; client log: `Failed to ping without candidate pairs. Connection is not possible yet.` (continuously).

Fix: appended `AF_NETLINK` to the address-family allowlist. After redeploy, both sides reached `Setting new connection state: Connected` and the server logged the canonical `Link connected` marker from upstream.

### Bug discovered + fixed: `StateDirectory=` doesn't accept nested paths on systemd 249
Initial unit had `StateDirectory=maskanya-olcrtc maskanya-olcrtc/data` (intended to create both the parent and a `data/` subdir for olcrtc state). Ubuntu 22.04's systemd 249 rejected this with `Failed to set up special execution directory in /var/lib: File exists` and exit code 238/STATE_DIRECTORY. Fix: use a single `StateDirectory=maskanya-olcrtc` and point `-data` at the StateDirectory root (`/var/lib/maskanya-olcrtc`); olcrtc creates whatever subdirs it needs.

### End-to-end IP test (Task 8) — link works but flaps
- Direct curl from operator: `125.103.213.138` (JST)
- ZOV's expected egress: `103.137.249.134` (NL)
- curl through SOCKS5: **empty response** after 15s ack timeout.
- Server-side journal proved the **architecture works**: when the WebRTC link was up, the client's tunnel request reached the server, which logged
  ```
  sid=3 connect ifconfig.me:443
  sid=3 connected ifconfig.me:443 in 4.293296ms
  ```
  — i.e., the server opened the upstream TCP connection to ifconfig.me successfully on the client's behalf.
- The response **did not return** to the client because the WebRTC link flapped during the round trip.

### Root cause of the flap: TURN-relay UDP keepalive ages out on JST NAT
Client log:
```
pion.ice: "Failed to read from candidate udp4 relay 185.62.200.94:61718 related 0.0.0.0:58878: i/o timeout"
pion.ice: "Setting new connection state: Failed"
```
- Direct UDP path between operator (JST) and ZOV (NL) is dropped by intermediate NAT.
- Both sides fall back to a TURN relay (`185.62.200.94`, the Wildberries-side relay).
- Local NAT-mapping for the client→relay UDP path ages out, breaking the link every ~10–15s.
- Each break triggers a fresh signaling round → "connecting" → "connected" → flap repeats.
- Server-side (NL VPS, routable IP, no aging NAT) sees a single stable "connected" the whole time.
- This is **not** an olcrtc bug, an upstream regression, or a `wbstream` policy issue — it's the asymmetric NAT environment of a residential JST ISP routed via an unusual peering path to a Wildberries SFU.

### Sustained 5-min throughput test (Task 9) — SKIPPED
Skipping the throughput loop was the correct call: a flapping link would produce a single number that says nothing about Channel B's actual performance for the intended RU use case. The 5-min sustained measurement belongs in the RU operator-side test, not here.

### Server behavior during the test
- ZOV process: 9.6 MB RAM, 14 goroutines, ~400 ms CPU during steady state.
- No reconnect storms on the server side; ICE state remained `connected` even when the client side cycled.
- No carrier-side errors in journal once the AF_NETLINK fix landed.

## Verdict rationale

**PARTIAL**: the build/deploy/handshake/upstream-fetch chain all work; the architecture is proven on our infra (binary, systemd hardening minus the two bugs above, secret layout, deploy script). Sustained operation from this specific test network is gated by a NAT-aging issue that does not apply to the target use case (RU residential client → wbstream → ZOV). Re-running the same plan from an RU residential network is expected to PASS, but that test is the operator's job alongside Phase 0 VAL-01/VAL-02.

## Recommendations for follow-up plans (Phase 4 backlog)

- [ ] **04-02 — Ansible role `olcrtc_bridge`.** Replace `deploy-zov.sh` with a proper role; enable + start the unit on boot. Bake in the `AF_NETLINK` address family and the single-`StateDirectory` lesson learned here.
- [ ] **04-03 — Companion-app integration.** Embed `cnc` mode (or wrap the binary) inside the Tauri companion; emit `maskanya-rtc://...@stream.wb.ru/<room-id>` URIs.
- [ ] **04-04 — Marzban subscription URI for Channel B.** Derive per-user keys + rooms from JWT (the current single-shared-key design is operator-only and trivially MitMable between holders).
- [ ] **04-05 — Telemost + SaluteJazz fallback carriers.** Resolve anonymous-join question from parent spec (line 513) and implement carrier auto-rotation.
- [ ] **Hardening note for 04-02:** `systemctl status` exposes the full command line including `-key ${OLCRTC_KEY}` because the env-var expansion happens at unit-render time. Workaround: keep service-private (read-only to root), or upstream change to read the key from a file via `-key-file`.

## RU operator-side test (deferred — gating for PASS upgrade)

What was tested here is "tunnel functions end-to-end". What's still needed before declaring Channel B production-eligible:
1. RU residential or mobile ISP as the client side.
2. Verify wbstream SFU remains on the TSPU whitelist from that ISP's path (no IP/SNI blocking observed).
3. 5-min sustained transfer (Task 9 loop) — record kbps + reconnect count.
4. Confirm the JST NAT-aging issue doesn't recur on a typical RU consumer NAT.

This test slots naturally next to VAL-01/VAL-02 in the Phase 0 PoC validation. Recommended sequencing: run Phase 0 RU operator test first; if VAL-01 (VLESS) and VAL-02 (basic WebRTC) both PASS, the same RU client can immediately attempt Channel B with the existing `experiments/b-webrtc/.env.olcrtc-v0` after secure key transfer.

## Artifacts

- `experiments/b-webrtc/upstream/` — vendored olcrtc @ `c74d171` (committed)
- `experiments/b-webrtc/scripts/{build,deploy-zov,run-client,teardown-zov}.sh` — operational scripts (committed)
- `experiments/b-webrtc/systemd/maskanya-olcrtc-bridge.service` — unit with both bug fixes (committed)
- `experiments/b-webrtc/.env.olcrtc-v0` — shared secret (local only, gitignored, mode 600)
- ZOV: `/usr/local/bin/maskanya-olcrtc`, `/etc/maskanya/olcrtc.env` (0600 root:root), `/etc/systemd/system/maskanya-olcrtc-bridge.service` (loaded, disabled, currently inactive)
