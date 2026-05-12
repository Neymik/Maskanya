# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-08)

**Core value:** A Russian user can browse the open internet reliably even during a whitelist-mode regional event.
**Current focus:** Phase 0 — PoC validation, with Phase 4 v0 (Channel B olcRTC) running in parallel.

## Current Position

Phase: 0 of 4 (PoC validation in progress; Phase 4 v0 PASS operator-side from JST)
Plan: 1 of 1 in current phase (Phase 0); 1 of 5 in Phase 4 done
Status: Phase 0 — VAL-01 multihop + VAL-03 fetch-relay PASSED operator-side, awaiting RU. Phase 4 v0 — operator-side **PASS** (4.7 Mbps sustained 5-min from JST, 0 errors, 0 disconnects).
Last activity: 2026-05-12 — Phase 4 v0 (Channel B olcRTC) operator-tested:
  • Upstream openlibrecommunity/olcrtc vendored @ c74d171 (master, PRE refactor/universal-carrier)
  • Cross-built linux-amd64 + darwin-arm64 via `mage cross`
  • Deployed to ZOV: `/usr/local/bin/maskanya-olcrtc`, systemd unit `maskanya-olcrtc-bridge.service` (loaded, disabled, inactive — manual-start only)
  • Two systemd-unit bugs found + fixed: must allow `AF_NETLINK` (pion ICE enumeration); `StateDirectory=` rejects nested paths on systemd 249. Memory record: `~/.claude/.../memory/project_olcrtc_systemd_bugs.md`
  • 5-min sustained test from JST → Wildberries TURN (Moscow) → ZOV NL: 168 MiB transferred, **4,682 kbps avg**, 0 errors, 0 disconnects
  • The initial "PARTIAL" reading was a debug-iteration artifact (broken AF_NETLINK + `MemoryDenyWriteExecute` causing initial-handshake flap); clean unit is rock-solid
  • Verdict: **PASS** — see `experiments/b-webrtc/RESULTS-olcrtc-v0.md`. RU operator-side test still useful as supplementary measurement but no longer gating.
Prior activity: 2026-05-11 — VAL-03 (Channel C, YC Function) deployed and operator-tested:
  • Function `image-thumbnailer-v2` (id `d4engb6fl2nijjdfh98g`) live on nodejs22 in folder b1gamurq8prfsf4dso64
  • Public access toggled via console (CLI allow-unauthenticated-invoke needs iam.editor which our SA lacks)
  • Empirical: YC API gateway intercepts `Authorization: Bearer ...` and 403s before handler runs.
    Switched to custom `X-Maskanya-Token` header — works correctly.
  • Operator test: function fetched ifconfig.me, returned full HTML, YC egress IP `185.206.167.220` visible.
    Auth gate verified (bad/missing token → 401 from handler).
  Plus VAL-01 status (from prior) — multihop chain still live on MSK→ZOV, awaiting RU empirical test.

Progress: [███████░░░] ~70% (VAL-01 + VAL-03 deployed & operator-tested awaiting RU; Phase 4 v0 PASS from JST — Channel B working end-to-end)

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| — | — | — | — |

**Recent Trend:**
- No completed plans yet.

## Accumulated Context

### Decisions

Captured in `.planning/PROJECT.md` "Key Decisions" table. Notable for execution:
- All public ports `:443` only (port discipline).
- ZOV `:443` becomes nginx_stream SNI demuxer in Phase 1; do not touch existing 13 vhosts directly.
- MSK `:443` is freshly available post-wipe; no production xray running there.

### Pre-existing host state (relevant for Phase 0/1 execution)

- ZOV: 13 production nginx vhosts on `:443`/`:80`, 20+ Docker containers, certbot, fail2ban, awg0 mesh on UDP/51820 — preserved per `host_vars/ZenithOfVastness.yml` `preserve_*` flags.
- MSK: post-wipe baseline. AWG mesh peer; nothing else.
- Production xray-maskanya on ZOV `:8443` is grandfathered but unused (Marzban not running per memory `project_zov_bootstrap_state.md` 2026-04-18). Phase 1 cutover removes it without service disruption.

### Open empirical unknowns (resolved by Phase 0)

- Does VLESS+Reality+XHTTP+chrome on `:443` actually pass current RU DPI from FirstVDS? (VAL-01)
- Does WebRTC work in a Russian browser at all? (VAL-02)
- Are YC Functions reachable from RU AND able to reach foreign internet? (VAL-03)

## Next Action

**Operator-side (RU client testing):** paste the v2 URI (regenerate via `source experiments/a-vless/keys-poc-a.sh && experiments/a-vless/scripts/gen-client-uri.sh`) into a xray-based client (Hiddify-Next/v2rayN/Karing — sing-box-only clients like NekoRay won't work, xhttp is xray-only). Run Task 6 from the plan:
- `curl --socks5 127.0.0.1:<client-port> -m 15 https://ifconfig.me` → expect `82.146.35.191`
- 5min sustained browsing test
- Record verdict in `experiments/a-vless/RESULTS.md`

**Then optional:** Task 10 (browser WebRTC viability via `experiments/b-webrtc/manual-test.html` on the RU device) and Task 13 (YC Function deploy + RU test).

**Rollback at any time:** `experiments/a-vless/scripts/rollback-to-production.sh` restores the production xray-maskanya config from the timestamped backup at `/etc/xray/config.json.pre-poc.bak.20260508-163555` on MSK.

**For autonomous resumption (`/gsd:autonomous` or similar):** plan resumes at Task 6 (RU empirical test); Tasks 0-5 already complete. After RESULTS.md commits land, plan resumes at Task 14 (ROADMAP/STATE finalize).

Full task-by-task breakdown: `.planning/phases/00-poc-validation/00-01-PLAN.md`.

**Channel B (Phase 4 v0) RU re-test:** once the RU operator is set up for VAL-01/VAL-02, run `./experiments/b-webrtc/scripts/run-client.sh` after the existing `.env.olcrtc-v0` is transferred over a secure channel. ZOV-side service stays as-is (start it before the test: `ssh ZenithOfVastness 'sudo systemctl start maskanya-olcrtc-bridge'`; stop after).

---
*State updated: 2026-05-12*
