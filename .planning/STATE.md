# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-08)

**Core value:** A Russian user can browse the open internet reliably even during a whitelist-mode regional event.
**Current focus:** Phase 0 — PoC validation

## Current Position

Phase: 0 of 3 (PoC validation)
Plan: 1 of 1 in current phase
Status: In progress — VAL-01 multihop + VAL-03 fetch-relay both PASSED operator-side; awaiting RU tests
Last activity: 2026-05-11 — VAL-03 (Channel C, YC Function) deployed and operator-tested:
  • Function `image-thumbnailer-v2` (id `d4engb6fl2nijjdfh98g`) live on nodejs22 in folder b1gamurq8prfsf4dso64
  • Public access toggled via console (CLI allow-unauthenticated-invoke needs iam.editor which our SA lacks)
  • Empirical: YC API gateway intercepts `Authorization: Bearer ...` and 403s before handler runs.
    Switched to custom `X-Maskanya-Token` header — works correctly.
  • Operator test: function fetched ifconfig.me, returned full HTML, YC egress IP `185.206.167.220` visible.
    Auth gate verified (bad/missing token → 401 from handler).
  Plus VAL-01 status (from prior) — multihop chain still live on MSK→ZOV, awaiting RU empirical test.

Progress: [██████░░░░] 55% (VAL-01 + VAL-03 deployed and operator-tested; both await RU empirical confirmation)

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

---
*State updated: 2026-05-08*
