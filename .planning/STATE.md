# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-08)

**Core value:** A Russian user can browse the open internet reliably even during a whitelist-mode regional event.
**Current focus:** Phase 0 — PoC validation

## Current Position

Phase: 0 of 3 (PoC validation)
Plan: 1 of 1 in current phase
Status: Ready to execute
Last activity: 2026-05-08 — Milestone v0.1 roadmap defined; Phase 0 spec + plan written

Progress: [░░░░░░░░░░] 0%

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

Execute Phase 0, Plan 00-01:

```bash
cd /Users/neymik/Documents/maskanya/experiments/a-vless
./scripts/keygen.sh > .env.poc-a
source .env.poc-a
./scripts/render.sh
./scripts/deploy.sh
./scripts/gen-client-uri.sh
# … operator-side smoke test, then RU empirical test, then RESULTS.md
```

Full task-by-task breakdown: `.planning/phases/00-poc-validation/00-01-PLAN.md`.

---
*State updated: 2026-05-08*
