# Maskanya — VLESS Reality Multihop VPN Service

**Date:** 2026-04-17
**Status:** Approved

## Overview

Maskanya is a VLESS+Reality based multihop VPN service for Russian users. It uses cheap RU-hosted entry nodes that forward traffic through foreign exit nodes, bypassing DPI while keeping costs low and minimizing legal exposure on Russian soil.

## Architecture

### Topology — Bipartite Entry × Exit Graph

```
Client (RU) ──VLESS+Reality──▶ Entry Node (RU) ──VLESS+Reality──▶ Exit Node (foreign) ──▶ Internet
                                     │
                                     ├── .ru / geoip:ru traffic → direct egress (no exit hop)
                                     └── all other traffic → exit node
```

- **Entry fleet** (RU, cheap VPS): MaskanyaHopMsk (Moscow), future: Kursk, Novosibirsk, Kemerovo, …
- **Exit fleet** (foreign): ZenithOfVastness (NL), MaskanyaExitKZ1 (Kazakhstan), future: Frankfurt, …
- Any entry can route to any exit. Geographic pairing (Siberia → KZ, European RU → NL) gives best latency.
- Each entry × exit pair is a named **chain** (e.g. `msk-nl`, `msk-kz`). Users see one VLESS URI per chain in their subscription.

### Split Routing at Entry

Entry nodes run Xray with routing rules:
- `geoip:ru` + `geosite:category-ru` destinations → direct egress from the entry node
- All other traffic → forward to the assigned exit node via VLESS+Reality outbound

This saves exit-node bandwidth and reduces latency for Russian domestic traffic.

### Host/Role Matrix

| Host | Location | Roles | SSH Alias |
|---|---|---|---|
| ZenithOfVastness | Netherlands | `mgmt`, `exit` (test/default) | `ZenithOfVastness` |
| MaskanyaExitKZ1 | Kazakhstan | `exit` | `MaskanyaExitKZ1` |
| MaskanyaHopMsk | Moscow, RU | `entry` | `MaskanyaHopMsk` |

ZenithOfVastness is dual-role (mgmt + exit) for cost savings during invite-only phase. Migration path: lift Marzban + MariaDB + Grafana to a dedicated `mgmt-1` host, update AWG peer list, swap DNS.

## Protocol Stack

### VLESS+Reality — Both Hops

- **Client → Entry:** VLESS+Reality, per-node randomized SNI from neutral-country decoy pool
- **Entry → Exit:** VLESS+Reality, independently randomized SNI from the same pool (different decoy than entry)

Both hops cross Russian border DPI, so both need Reality camouflage.

### Reality Decoy Domain Pool

Per-node randomized at Ansible provisioning time. All domains must be TLS 1.3, HTTP/2, X25519, not blocked in Russia, not US-owned (avoid collateral RKN blocking of US tech brands).

Initial pool:
- `www.lovelive-anime.jp` (JP)
- `www.nintendo.co.jp` (JP)
- `www.sony.jp` (JP)
- `www.asus.com` (TW)
- `www.samsung.com` (KR)
- `www.lg.com` (KR)
- `www.naver.com` (KR)
- `www.kakao.com` (KR)

Pool is expanded in git — adding a domain = one-line change. Each domain gets a TLS 1.3 + H2 + X25519 sanity check during Ansible run.

Entry and exit on the same chain MUST use different decoys (compartmentalization — if one decoy gets collateral-blocked, only one hop is affected).

## Control Plane

### Marzban Panel

Open-source panel running on mgmt host (ZenithOfVastness). Provides:
- Multi-node support (gRPC/mTLS to each marzban-node agent)
- Per-user subscription URLs (clients fetch updated VLESS configs)
- Traffic quotas, user expiry dates
- REST API (future SaaS billing layer integrates here)
- Telegram bot integration

Database: MariaDB (production-grade, backed up nightly).

### Subscription Model

- Each user gets one subscription URL: `https://sub.maskanya.animeenigma.ru/sub/{token}`
- Client (Hiddify, v2rayN, sing-box, Streisand) fetches the URL, receives one VLESS URI per chain the user is entitled to
- Adding a new entry/exit node → Marzban regenerates configs → users see the new chain on next subscription refresh
- Option 1 (now): explicit N×M chain list. Option 2 (later): smart chain recommendations with real-time ping tests.

### Service Model

Invite-only for now. Architecture is SaaS-ready from start — Marzban API supports future signup/billing/abuse layers without replacing the core.

## Networking

### AmneziaWG Control Mesh (not plain WireGuard)

WireGuard is blocked by Russian DPI. AmneziaWG is the Amnezia team's WG fork that injects randomized junk packets into handshakes, evading WG fingerprinting. Kernel module on Linux 5.10+, `awg`/`awg-quick` CLI.

- **Topology:** star, hub at mgmt (ZenithOfVastness)
- **Subnet:** `10.77.0.0/24`
  - `10.77.0.1` — mgmt hub
  - `10.77.0.10+` — entry nodes
  - `10.77.0.50+` — exit nodes
  - `10.77.0.100+` — operator laptops
- **Junk params** (`Jc/Jmin/Jmax/S1/S2/H1-H4`) defined once in Ansible `group_vars/all.yml`, identical across all peers
- **Carries:** Marzban gRPC, Prometheus scrape, SSH admin, Loki push (future), Xray stats API
- **Does NOT carry:** user VPN traffic

Applied uniformly across the fleet (including foreign-to-foreign) so the hub speaks one protocol.

**Fallback path (documented, not built):** If AmneziaWG starts getting blocked, control channel moves inside a Reality-wrapped TCP tunnel via xray/gost. Same 10.77.0.0/24 addressing, only transport swaps.

### Admin Access

Operator laptop joins the AmneziaWG mesh. All admin surfaces (SSH, Marzban UI, Grafana, Prometheus) bind to the mesh interface only. No admin exposure on public internet.

### Public-Facing Surfaces

| Surface | Host | Port | Purpose |
|---|---|---|---|
| Reality VLESS | entries | 443 | user data plane ingress |
| Reality VLESS | exits | 443 | entry→exit data plane (source-IP allowlisted to entry WAN IPs) |
| Subscription HTTPS | mgmt | 443 | `GET /sub/{token}` |
| AWG | all | UDP/random | control mesh, peer-IP allowlisted |

Everything else is mesh-only.

### Domains & DNS

- **Base domain:** `maskanya.animeenigma.ru`
- **DNS:** Cloudflare, no proxy (DNS records only, CF not in data path)
- **ACME:** Let's Encrypt via DNS-01 with Cloudflare API token (scoped to zone)
- **Subdomains:**
  - `sub.maskanya.animeenigma.ru` — public subscription endpoint
  - `panel.maskanya.animeenigma.ru` — Marzban UI (mesh-only; public A record for LE cert issuance)
  - `grafana.maskanya.animeenigma.ru` — Grafana (mesh-only, same pattern)

**TLD risk note:** `.ru` is Russian-jurisdiction — RKN can force-revoke. Mitigation: register a dormant backup domain on a foreign TLD (`.xyz`, `.li`, `.st`) pre-beta. Migration planned post-beta.

## Components per Host Type

### Entry Nodes (RU, minimal-footprint)

- `xray-core` (data plane: Reality inbound + outbound + split routing)
- `marzban-node` agent (gRPC/mTLS client to panel)
- `node_exporter` (Prometheus metrics via mesh)
- `amneziawg` (control mesh client)
- `chrony` (NTP — Reality rejects >60s clock skew)
- `unattended-upgrades` / `dnf-automatic`
- `journald` with `Storage=volatile`, size-capped — no persistent logs, no user IPs retained
- **Nothing else.** No panel, no DB, no Grafana, no certs, no state worth seizing.

### Exit Nodes (foreign)

- Same base as entry (xray, marzban-node, node_exporter, AWG, chrony, upgrades)
- No split routing — all traffic egresses to internet
- nftables: Reality port open only to entry WAN IPs (allowlist)

### Management Host (foreign, on ZenithOfVastness)

- `marzban` panel: Docker Compose (FastAPI + MariaDB + nginx + LE)
- `prometheus` + `grafana` + `loki` + `promtail`
- `blackbox_exporter` (synthetic probes to entry Reality ports)
- `alertmanager` → Telegram bot
- `restic` (nightly encrypted backup to S3-compatible storage)
- `amneziawg` hub
- Admin SSH + panel UI behind mesh only; public surface = subscription endpoint + healthcheck

## Infrastructure as Code

### Ansible-Only (no Terraform)

Mixed VPS providers (RU: Aeza/Timeweb, KZ: local, NL: Hetzner-like) without uniform TF support. Ansible owns the full lifecycle from a fresh SSH-able box. TF module for Hetzner exits can be layered later if needed.

### Repo Layout

```
maskanya/
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventory/
│   │   └── production/
│   │       ├── hosts.yml
│   │       ├── group_vars/
│   │       │   ├── all.yml           # AWG junk params, decoy pool, versions
│   │       │   ├── mgmt.yml
│   │       │   ├── entries.yml
│   │       │   └── exits.yml
│   │       └── host_vars/
│   │           ├── ZenithOfVastness.yml
│   │           ├── MaskanyaHopMsk.yml
│   │           └── MaskanyaExitKZ1.yml
│   ├── roles/
│   │   ├── common/
│   │   ├── firewall/
│   │   ├── amneziawg/
│   │   ├── node_exporter/
│   │   ├── xray_common/
│   │   ├── xray_entry/
│   │   ├── xray_exit/
│   │   ├── marzban_node/
│   │   ├── marzban_panel/
│   │   ├── monitoring/
│   │   └── backup/
│   └── playbooks/
│       ├── site.yml
│       ├── bootstrap.yml
│       ├── add-entry-node.yml
│       ├── add-exit-node.yml
│       ├── rotate-reality-keys.yml
│       └── rotate-awg-keys.yml
├── secrets/
│   ├── .sops.yaml
│   ├── marzban_admin.yml
│   ├── cloudflare_api_token.yml
│   ├── s3_backup_credentials.yml
│   └── grafana_admin.yml
├── docs/
│   ├── superpowers/specs/
│   ├── runbooks/
│   └── architecture/adr/
├── scripts/
│   ├── new-entry-bootstrap.sh
│   └── new-exit-bootstrap.sh
├── .github/workflows/
│   ├── lint.yml
│   └── validate.yml
├── .sops.yaml
├── Makefile
└── README.md
```

### Secrets — SOPS + age

- All files in `secrets/` encrypted with age recipients (operator public keys)
- Ansible reads via `community.sops` lookup plugin — secrets never hit plaintext on disk
- Pre-commit hook enforces: no plaintext secret commits
- Age master keys stored in 1Password + offline paper backup

### Key Generation

- Reality private keys + AmneziaWG private keys generated **on-node** during first Ansible run
- Private keys never leave the box
- Public keys committed to `host_vars/` for mesh/Reality config rendering
- Rotation playbooks do regen + coordinated peer-config push

### Bootstrap Sequence (new node, ~10 min)

1. Order VPS, get root SSH + IP
2. Add SSH alias to `~/.ssh/config`
3. Append stub to `hosts.yml`, create `host_vars/<Name>.yml`
4. `make bootstrap HOST=<Name>` — hardening, admin user, baseline packages, AWG mesh join
5. `make add-entry HOST=<Name>` (or `add-exit`) — role-specific stack, key gen, Marzban registration
6. Marzban regenerates configs; clients see new chain on next subscription refresh

### CI — GitHub Actions

- `ansible-lint` + `yamllint` + `shellcheck`
- `sops --decrypt` smoke test
- `ansible-playbook --syntax-check` on all playbooks
- `ansible-playbook --check --diff` against mock inventory
- Block merge on red

### Makefile

Operator UX — single commands: `make lint`, `make apply`, `make bootstrap HOST=…`, `make add-entry HOST=…`, `make rotate-keys`.

## Observability

### Metrics Collection (all over AmneziaWG mesh)

- `node_exporter` on every host → system metrics
- `xray-exporter` on entries + exits → Reality handshake counters, per-user traffic
- Marzban Prometheus endpoint → active users, node health, subscription requests
- `blackbox_exporter` on mgmt → synthetic TLS probes to each entry's public Reality port every 30s
- **No access logs with user IPs** — Xray access log disabled on entries

### Storage

- Prometheus: 15d local retention
- Loki: 30d retention, mgmt services only (not RU entries)
- Grafana dashboards: committed to git as JSON, provisioned declaratively

### Dashboards

1. **Fleet overview** — node up/down, handshake RPS per chain, active users per chain
2. **Per-chain health** — latency (blackbox), throughput, Reality error rate
3. **Capacity** — CPU/mem/disk/net per node
4. **Marzban ops** — subscription fetches, user count, cert expiry countdown

### Alerting — Alertmanager → Telegram Bot

| Alert | Severity | Condition |
|---|---|---|
| Node down | critical | `up == 0` for 2m |
| Xray down | critical | xray exporter down for 1m |
| AWG peer disconnected | critical | handshake age > 5m |
| Reality error rate | warning | > 5% over 10m |
| Public port unreachable | critical | blackbox fails 3× |
| Disk usage | warning | > 80% for 15m |
| Cert expires soon | warning | < 14 days |
| Backup stale | critical | snapshot age > 48h |
| Subscription 5xx | critical | > 1% over 5m |

## Backups

### What We Back Up

| Data | Source | Destination | Retention |
|---|---|---|---|
| Marzban MariaDB dump | mgmt | S3-compatible storage (encrypted) | 7 daily + 4 weekly + 3 monthly |
| Marzban config volumes | mgmt | same | same |
| `/etc` on mgmt | mgmt | same | same |
| Grafana dashboards | git | git history | — |
| Ansible inventory + SOPS | git | git provider | — |

### What We Do NOT Back Up

- Reality private keys (regenerate on rebuild — one chain offline until users refetch subscription)
- AmneziaWG private keys (regenerate + re-peer)
- Prometheus/Loki data (ephemeral)
- RU entry node OS state (full rebuild <10min via Ansible)

### Mechanics

- restic → S3-compatible storage, nightly via systemd timer
- Stale-backup alert if snapshot > 48h
- Restore drill: quarterly, runbook-driven, tested on throwaway VPS

## Security

### Per-Host Hardening (via `common` role)

- SSH: key-only, no root, non-standard port, `MaxAuthTries 3`
- `unattended-upgrades` with auto-reboot in maintenance window (03:00 local, jittered)
- `fail2ban` on mgmt for subscription endpoint (rate-limit 404 tokens)
- `chrony` for time sync
- Kernel sysctl hardening: disable unnecessary IP forwarding, rp_filter, disable source routing, tcp_syncookies
- nftables as primary firewall (no ufw)

### nftables per Role

- **Entry:** 443/tcp from anywhere; AWG from mgmt peer only; SSH from mesh only; drop else
- **Exit:** 443/tcp from entry WAN IPs only (allowlist); AWG from mgmt; SSH from mesh; drop else
- **Mgmt:** 443/tcp public (subscription only); AWG from all peers + operator; SSH from mesh; drop else

### Incident Response (documented in runbooks)

1. **RU entry seized:** rotate Reality keys, remove from inventory, Marzban re-issues configs. Users pick another chain.
2. **Mgmt compromised:** rotate all secrets, restore DB from backup onto fresh host, re-issue subscription URLs.
3. **Age key compromised:** rotate SOPS recipients, re-encrypt all secrets, revoke key.
4. **User token leaked:** rotate single user's Marzban subscription token.

## Phasing

### Phase 1 — Foundation (mgmt + first chain)

**Goal:** One working chain `MaskanyaHopMsk → ZenithOfVastness`, one user connects.

1. Repo scaffold: Ansible layout, SOPS, CI, Makefile
2. `common` role: SSH hardening, chrony, admin user, unattended-upgrades
3. `amneziawg` role: mesh ZenithOfVastness ↔ MaskanyaHopMsk + operator laptop
4. `firewall` role: nftables templates per role
5. `marzban_panel` role on ZenithOfVastness: Docker Compose + nginx + LE
6. `xray_exit` role on ZenithOfVastness: Reality inbound, freedom outbound
7. `xray_entry` role on MaskanyaHopMsk: Reality inbound/outbound + split routing
8. `marzban_node` role on both
9. Create test user, generate subscription URL, connect from RU client
10. Verify: youtube.com via NL, yandex.ru via MSK direct

**Exit criterion:** Human connects from Russia, browses foreign + domestic sites through correct paths.

### Phase 2 — Observability + Backups

**Goal:** Monitor the fleet and recover from disaster.

1. `node_exporter` on all hosts
2. `monitoring` role: Prometheus + Grafana + Loki + blackbox_exporter
3. Grafana dashboards committed as JSON
4. Alertmanager → Telegram bot
5. `backup` role: restic → S3 nightly
6. Restore runbook tested on throwaway VPS

**Exit criterion:** Grafana shows green fleet, Telegram fires test alert, restic restore produces working Marzban.

### Phase 3 — Second Exit + Fleet Scaling

**Goal:** Multi-exit works, adding a node is one command.

1. Onboard MaskanyaExitKZ1: bootstrap → AWG → xray_exit → marzban_node
2. Chain `msk-kz` visible in subscriptions alongside `msk-nl`
3. Verify both chains work concurrently
4. Test `add-entry-node.yml` with throwaway RU VPS
5. Test `add-exit-node.yml` similarly
6. Test key rotation playbooks end-to-end
7. CI validated: lint → syntax-check → dry-run passes on PR

**Exit criterion:** `make add-entry HOST=TestNode` takes fresh VPS to live in <10 minutes.

### Post-Beta Backlog

- Dedicated mgmt host (lift off ZenithOfVastness)
- Backup domain migration (off `.ru` TLD)
- Smart chain recommendations (real-time ping tests)
- Self-serve SaaS: signup, billing, abuse handling
- AmneziaWG fallback transport (Reality-wrapped control tunnel)
