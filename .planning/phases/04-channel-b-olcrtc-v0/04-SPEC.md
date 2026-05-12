# Phase 4 v0 — Channel B olcRTC tunnel (manual deployment)

## What this phase delivers

A working end-to-end **olcRTC WebRTC-over-wbstream tunnel** between the operator's local machine and `ZenithOfVastness` (NL exit), driven by the upstream `openlibrecommunity/olcrtc` binary at a pinned commit. Operator-tested: a `curl` through the client's SOCKS5 listener returns ZOV's NL egress IP, with traffic carried inside a WebRTC session on Wildberries' wbstream SFU.

## What it explicitly does NOT deliver

- **No Ansible role.** Manual scp + systemd deploy. The `olcrtc_bridge` Ansible role from the design spec (Channel B section, line 428) is a deferred follow-up plan (04-02), out of scope for v0.
- **No companion app integration.** No `maskanya-rtc://` URI emission, no Tauri changes, no Marzban subscription wiring. Operator drives the client by hand.
- **No multi-room / multi-user.** Single shared room + single shared key. User-facing multi-tenancy is later phase work.
- **No Telemost carrier.** Wbstream + datachannel only, per upstream's recommendation (max speed, min latency, no account required for self-generated room IDs). Telemost adds an anonymous-join open question (design-spec line 513) we don't need to answer to ship v0.

## Why this exists / how it relates to the parent spec

The canonical design spec (`docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md`, "Channel B — olcRTC" section) defined Channel B as a Phase 4 deliverable predicated on building a custom `pion-webrtc`-based bridge daemon. Upstream `openlibrecommunity/olcrtc` now ships working binaries with a stable CLI surface, which collapses that build-from-scratch effort into "vendor + scp + systemctl start".

This v0 brings forward the **infrastructure proof** of Channel B (does the tunnel work end-to-end on our hosts) without paying for the full Phase 4 scope (companion app, subscription delivery, room-code derivation from JWT, multi-user). Doing so:
1. Validates the upstream binary against ZOV's network environment before committing to it.
2. Gives Channel A operators a "panic-button" side-channel they can hand-distribute today if Channel A is burnt.
3. Reduces Phase 4 risk: by the time we wire it into the companion app, the underlying tunnel is already known to work on our infra.

## Pinned upstream commit

To be selected at Task 2 time. Candidate: latest master commit predating the `refactor/universal-carrier` merge. README warns the refactor merges "within approximately one week"; pin **before** the merge to avoid CLI-flag drift. Recorded in `experiments/b-webrtc/upstream/UPSTREAM_COMMIT`.

## Carrier + transport

- Carrier: **wbstream** (Wildberries `stream.wb.ru`) — no Yandex account required for self-generated room IDs.
- Transport: **datachannel** — SCTP over WebRTC DataChannel, fastest sub-transport per upstream docs.

## Threat model deltas vs parent spec

Same as parent spec's Channel B section. Two notable v0-specific notes:
- **Room ID + key live in two places:** operator's local `.env.olcrtc-v0` (gitignored) and ZOV's `/etc/maskanya/olcrtc.env` (root-only). Distribution out-of-band only.
- **Single room = single tenant.** Any third party with the key can MitM the encryption layer trivially (it's a symmetric secret). v0 is operator-only; do not hand the key to users.

## Success criteria (what must be TRUE)

1. `experiments/b-webrtc/upstream/UPSTREAM_COMMIT` exists, pinning a specific olcrtc commit hash + date.
2. `experiments/b-webrtc/upstream/` contains the vendored olcrtc source tree (excluding `.git/`, `.github/`, `mobile/`); LICENSE + `readme.md` preserved verbatim.
3. ZOV has `/usr/local/bin/maskanya-olcrtc` (linux-amd64 binary) + `/etc/maskanya/olcrtc.env` (mode 0600) + `/etc/systemd/system/maskanya-olcrtc-bridge.service` (not enabled, manual-start).
4. Operator's local machine has the host-platform binary at `experiments/b-webrtc/build/maskanya-olcrtc-<os>-<arch>` (darwin-arm64 / darwin-amd64 / linux-amd64) + `experiments/b-webrtc/.env.olcrtc-v0` (gitignored).
5. With `maskanya-olcrtc-bridge.service` running on ZOV and the operator running `maskanya-olcrtc -mode cnc ...` locally, `curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me` returns ZOV's public IPv4.
6. 5 minutes of `curl`-driven traffic through the tunnel without disconnect. Throughput is recorded in RESULTS but is informational, not gating — the parent spec notes 0.5–2 Mbps as the realistic WebRTC-SFU range, so PASS requires "no disconnect", PARTIAL acceptable if rate is degraded but tunnel survives.
7. `experiments/b-webrtc/RESULTS-olcrtc-v0.md` exists with verdict (PASS / PARTIAL / FAIL), tested config snapshot, throughput notes, and recommendation.
8. ROADMAP.md gains a Phase 4 entry referencing this plan.

## Out of scope (call out explicitly so future plans can pick them up)

- Ansible role for `olcrtc_bridge` (planned as plan 04-02).
- Companion app embedding (planned for plan 04-03 alongside Phase 3's Tauri work).
- Multi-room / per-user key derivation from JWT (planned for plan 04-04, requires Marzban subscription template extensions).
- Production hardening: prom metrics, log rotation, automated room rotation, fallback carriers (Telemost, SaluteJazz) — deferred.

---
*Spec drafted: 2026-05-12*
