# Channel B v0 — olcRTC manual deploy results

**Verdict:** PASS

**Tested:** 2026-05-12
**Operator:** Neymik
**Network:** operator workstation on JST residential ISP → Wildberries TURN relay (Moscow) → ZenithOfVastness (NL VPS)

> The operator-side test ran from a Japanese residential ISP — geographically and network-topologically the *worst* configuration for this channel (RU TURN reached via Tokyo→US→Europe→Moscow long-haul, ~268 ms RTT). The fact that the link is stable at 4.7 Mbps sustained from JST is a stronger result than the parent spec anticipated. The intended production topology (RU client → RU TURN ~10 ms → NL ZOV 43 ms) should be at least as fast.

## Stack tested

- Upstream: `openlibrecommunity/olcrtc @ c74d171` (2026-05-11 17:40 +0300, master, PRE `refactor/universal-carrier` merge — see `experiments/b-webrtc/upstream/UPSTREAM_COMMIT`)
- Carrier: `wbstream` (Wildberries `stream.wb.ru`)
- Transport: `datachannel`
- TURN relay observed: `185.62.200.94` (`WILDBERRIES-NETWORK-RU`, Moscow)
- Server: ZenithOfVastness (Ubuntu 22.04, systemd 249), unit `maskanya-olcrtc-bridge.service`
- Client: operator workstation (darwin-arm64), `./experiments/b-webrtc/scripts/run-client.sh`
- Shared secrets: 32-byte ChaCha20 key + UUIDv7 RoomID; gitignored locally, root-only at `/etc/maskanya/olcrtc.env` (mode 0600) on ZOV.

## End-to-end IP test (Task 8)

| Path | IP |
|---|---|
| Direct from operator | `125.103.213.138` (JST) |
| Via olcrtc SOCKS5 (`127.0.0.1:1080`) | `103.137.249.134` (ZOV NL egress) |
| 5 back-to-back curl bursts | 5/5 succeeded, HTTP 200 in ~0.9 s each |

## Sustained 5-minute transfer test (Task 9)

| Metric | Value |
|---|---|
| Elapsed | 301 s |
| Attempts (1 MiB each via `speed.cloudflare.com/__down`) | 168 |
| Total transferred | 168 MiB |
| **Average sustained throughput** | **4,682 kbps** (≈ 4.7 Mbps) |
| Errors | **0** |
| Disconnects (`peer connection state` events during 5-min window) | **0** |
| Server side journal | 168 clean `sid=N connect ifconfig.me:443` / `sid=N connected in ~4 ms` pairs |

For reference, the parent spec (`docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md`, line 355) projects 0.5–2 Mbps as realistic. We measured 4.7 Mbps — over 2× the upper end — from Japan.

## Bugs found and fixed during the run

### Bug 1: `RestrictAddressFamilies` must include `AF_NETLINK`

Initial unit had `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`. pion-webrtc enumerates network interfaces via `AF_NETLINK` (`route ip+net: netlinkrib`). Without it, the server gathered zero ICE candidates and the client log spammed `Failed to ping without candidate pairs. Connection is not possible yet.` forever; server logged `connect to room: could not connect after timeout`.

**Fix:** appended `AF_NETLINK` to the address-family allowlist. After redeploy, both sides reached `Setting new connection state: Connected` and the server logged the canonical `Link connected` marker.

### Bug 2: `StateDirectory=` rejects nested paths on systemd 249

Initial unit declared `StateDirectory=maskanya-olcrtc maskanya-olcrtc/data`. Ubuntu 22.04 systemd 249 rejected this with `Failed to set up special execution directory in /var/lib: File exists`, exit code `238/STATE_DIRECTORY`, then 10-second restart loop. Newer systemd accepts nested paths; 249 doesn't.

**Fix:** single `StateDirectory=maskanya-olcrtc`; point `-data /var/lib/maskanya-olcrtc` at the root; olcrtc creates its own subdirs.

Both fixes are committed in `experiments/b-webrtc/systemd/maskanya-olcrtc-bridge.service`. Memory record at `~/.claude/.../memory/project_olcrtc_systemd_bugs.md` for the future Ansible role (04-02).

## Server behavior during the test

- ZOV process: 9.6 MB RAM, 14 goroutines, ~400 ms CPU during steady state.
- Zero reconnects, zero ICE state changes after initial handshake.
- No carrier-side errors after the AF_NETLINK + StateDirectory fixes.

## Why this works from Japan despite the long path

(Documented for future operators who think the RU-only-from-RU assumption is binding.)

The WebRTC relay at `185.62.200.94` is in Wildberries' Moscow network. The path:
```
JST operator → Tokyo transit → US → Europe (Telia) → RU TURN → NL ZOV
```
Round-trip latency: 268 ms (vs 226 ms direct to ZOV in NL — Amsterdam is closer to Tokyo by network than Moscow is, despite geography).

Once a steady-state link is established, pion-webrtc's UDP-over-DTLS-over-TURN multiplexing tolerates the latency fine. The 5-min sustained 4.7 Mbps confirms this. Loss is low enough on Telia's premium backbone for SCTP retransmission to keep up. The initial-handshake "flap" we feared was actually leftover debug-iteration state from before the AF_NETLINK and `MemoryDenyWriteExecute` fixes landed — once the unit is clean, the link starts up cleanly and stays up.

## Open questions for follow-up plans (NOT blockers for v0 PASS)

- **`systemctl status` exposes `-key` in plaintext.** Visible to root only; not a v0 issue, but for production switch to `-key-file` (would need upstream support) or accept the limitation.
- **TURN relay assignment is non-deterministic.** Sometimes we got a Wildberries relay reachable via Europe; could in theory get one reachable only via worse paths. Resilient to single failures via ICE restart, but worth monitoring.
- **Single shared key per room.** Operator-only design; per-user keys via JWT → plan 04-04.

## Phase 4 backlog

- [ ] **04-02 — Ansible role `olcrtc_bridge`.** Replace `deploy-zov.sh` with a proper role; enable + start on boot. Bake in `AF_NETLINK` allowlist + single `StateDirectory`.
- [ ] **04-03 — Companion-app integration.** Embed `cnc` mode in Tauri; emit `maskanya-rtc://...@stream.wb.ru/<room-id>` URIs.
- [ ] **04-04 — Marzban subscription URI for Channel B.** Per-user JWT-derived keys + rooms.
- [ ] **04-05 — Telemost + SaluteJazz fallback carriers.** Resolve anonymous-join question from parent spec line 513; implement carrier auto-rotation.

## RU operator-side validation (still pending — supplementary, not gating)

This v0 already PASSes from the worst-case test topology. An RU residential operator test should also PASS and will give a real production latency/throughput number (expected: ~5–20 ms client→relay, 43 ms relay→ZOV, sub-100 ms total). Sequencing: alongside Phase 0 VAL-01/VAL-02, transfer the existing `.env.olcrtc-v0` to the RU operator over a secure channel; run `./experiments/b-webrtc/scripts/run-client.sh` on their machine.

## Artifacts (all committed)

- `experiments/b-webrtc/upstream/` — vendored olcrtc @ `c74d171`
- `experiments/b-webrtc/scripts/{build,deploy-zov,run-client,teardown-zov}.sh`
- `experiments/b-webrtc/systemd/maskanya-olcrtc-bridge.service` — clean unit with both fixes
- `experiments/b-webrtc/.env.olcrtc-v0` — shared secret (local only, gitignored, mode 600)
- ZOV: `/usr/local/bin/maskanya-olcrtc`, `/etc/maskanya/olcrtc.env` (0600 root:root), `/etc/systemd/system/maskanya-olcrtc-bridge.service` (loaded, disabled, **currently inactive** — operator stops it after testing per v0 design)
