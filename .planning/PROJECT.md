# Maskanya

## What This Is

A VLESS+Reality multihop VPN service for Russian users — invite-only during beta, SaaS-ready architecture. Cheap RU-hosted entry node forwards to a foreign exit; clients use the same subscription across three resilience tiers (VLESS direct, YC Function tunnel, WebRTC over Telemost) so a single block wave doesn't kill the service.

## Core Value

A Russian user can browse the open internet reliably even during a whitelist-mode regional event — when generic VPN providers go dark, Maskanya keeps working because the fallback channels ride on whitelist-resident Yandex infrastructure.

## Requirements

### Validated

(None yet — ship to validate)

### Active

See `REQUIREMENTS.md` for the full traceable list. Headlines for milestone v0.1:

- [ ] Channel A (primary VLESS path) survives current RU DPI when configured per the May 2026 design
- [ ] Channel C (Yandex Cloud Functions fallback) reachable from RU AND able to fetch foreign URLs
- [ ] Channel B (WebRTC viability) — protocol-level smoke test passes in a Russian browser
- [ ] Marzban serves a single subscription that emits all three URIs; revoking a user kills all three channels for them

### Out of Scope (v0.1)

- Multi-region exit (`MaskanyaExitKZ1` deferred — single ZOV exit suffices for invite-only)
- olcRTC bridge daemon production-readiness — the Habr article marks it pre-alpha; v0.1 only validates browser-side WebRTC works
- Mobile-native client — desktop companion app only
- Public registration — invite-only stays
- Auto-rotating Reality SNIs / shortIds — operator does this manually for now

## Context

- **Two existing hosts.** `ZenithOfVastness` (NL) is a shared host — 13 production nginx vhosts on `:443` and 20+ Docker containers must be preserved. `MaskanyaHopMsk` (Moscow, FirstVDS) is dedicated and was wiped post-bootstrap; rebuilds from scratch.
- **AmneziaWG control mesh.** `awg1` on UDP/51821, hub `10.77.0.1` on ZOV, spoke `10.77.0.10` on MSK. Used for stats/RPC; no user traffic.
- **Pre-existing operator memory.** See `~/.claude/projects/.../memory/MEMORY.md` for project history, host preservation contracts, and partial-bootstrap state from 2026-04-18.
- **May 2026 RU regulatory regime.** Documented in detail in `docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md` "Why this spec exists" and "Threat model".

## Constraints

- **Hosts**: ZOV + MSK only — no provider migration, no new VPS in v0.1. (User decision after weighing YC/Timeweb migration trade-offs.)
- **Port discipline**: every public listener on `:22 / :80 / :443` only. Anything else is at risk under the May 2026 RU DPI regime, including alt-HTTPS ports like `:8443`/`:2053`.
- **ZOV preservation**: 13 production nginx vhosts, 20+ Docker containers, existing `awg0` on UDP/51820, certbot, fail2ban, timesyncd — none modified. Maskanya additions are namespaced.
- **Tech stack**: Ansible-only IaC (no Terraform yet, except for YC Function deployment). xray-core ≥ v25.x for XHTTP+stream-one+Vision. SOPS+age for secrets. restic→S3 for backups.
- **Budget**: marginal cost ≈ ₽300/mo for MSK + per-user YC GB egress (~₽250/mo at 50 users × 5 GB). Free tier of YC Functions covers most usage.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Three parallel channels (A/B/C), not a single hardened VLESS | Single-channel designs die when whitelist mode flips on; YC- and Telemost-resident endpoints structurally survive | — Pending |
| Keep MSK on FirstVDS, not migrate to YC/Timeweb | User constraint — accepted operational risk in exchange for not running on YC ToS-prohibited proxy infra | — Pending (validates in Phase 0) |
| nginx_stream SNI-demux on ZOV `:443` instead of moving xray to `:8443` | Port discipline: only `:443` is safe under May 2026 regime; ZOV must demux multiple `:443` services | — Pending (Phase 1) |
| Marzban as single source of truth, NOT three separate user systems | Lower complexity, shared quotas, single subscription URL | — Pending (Phase 3) |
| olcRTC deferred to post-v0.1 milestone | Habr marks it pre-alpha; building a Pion bridge daemon is large scope and Channel B is last-resort | ✓ Good (clears v0.1 scope) |

---
*Last updated: 2026-05-08 after milestone v0.1 scope lock-in*
