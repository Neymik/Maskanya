# Maskanya — VLESS Reality Multihop VPN Service

**Date:** 2026-04-17
**Status:** SUPERSEDED on 2026-05-08 by `2026-05-08-three-channel-vpn-design.md`. The single-channel VLESS+Reality+Vision+TCP design below was overtaken by the May 2026 RU regulatory regime (whitelist-mode L3 filtering, behavioral DPI, May 1 cross-border traffic charges). Hosts (`ZenithOfVastness`, `MaskanyaHopMsk`) and the AmneziaWG control mesh are unchanged; the protocol stack and per-host responsibilities are rewritten. Read the new spec first.

---

**Original Status (2026-04-17):** Approved (revised 2026-04-17 after live-host exploration — see "Live-Host Constraints" below)

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
| ZenithOfVastness | Netherlands | `mgmt`, `exit` (test/default, shared-use) | `ZenithOfVastness` |
| MaskanyaExitKZ1 | Kazakhstan | `exit` (dedicated) | `MaskanyaExitKZ1` |
| MaskanyaHopMsk | Moscow, RU | `entry` (dedicated) | `MaskanyaHopMsk` |

ZenithOfVastness is dual-role (mgmt + exit) for cost savings during invite-only phase, and shared-use (runs 13 unrelated vhosts + 20+ Docker containers for other projects). Migration path: lift Marzban + MariaDB + Grafana to a dedicated `mgmt-1` host, update AWG peer list, swap DNS.

## Live-Host Constraints

Live hosts were explored on 2026-04-17 before provisioning. Both come with pre-existing state that shapes the implementation plan — the spec below reflects those constraints. Where the spec says "preserve X", the `common` and `firewall` roles gate subsystems behind `preserve_*` markers in `host_vars/ZenithOfVastness.yml`.

### ZenithOfVastness (NL, dual-role) — PRESERVATION-FIRST

Already running at exploration time:
- **nginx** serving 13 production vhosts on `:80`/`:443` (gitea, uptime-kuma, kino-site, ai-planner, animeenigma-saas-*, etc.) — we must NOT take over port 443
- **20+ Docker containers** (gitea, postgres, mariadb, shadowsocks, MTProto proxy, x-ui Xray panel, …) — Docker owns its iptables chains
- **Existing AmneziaWG tunnel** on interface `awg0` @ `10.0.0.10` / UDP 51820 — unrelated mesh from another project
- **certbot** issuing per-subdomain Let's Encrypt certs via HTTP-01 through existing nginx
- **fail2ban** + **systemd-timesyncd** active and working

**Implications:**
- Reality exit listens on alt port **`8443`**, not `443`
- Our AWG mesh uses separate interface **`awg1`** on UDP **`51821`** (both 51820 and awg0 are taken)
- Firewall is **additive iptables** (installing nftables would fight Docker's chains)
- Subscription and panel/grafana added as new vhosts inside existing nginx (not a new nginx instance)
- ACME uses **HTTP-01** via existing certbot (matches existing pattern; no Cloudflare API token needed for Phase 1)
- `common` role skips chrony (use existing timesyncd), fail2ban reinstall, and any nftables install
- All new systemd units / binaries / config paths are namespaced: `xray-maskanya.service`, `awg-quick@awg1`, `/usr/local/bin/xray-maskanya`, `/etc/amneziawg/awg1.conf`, `/etc/amneziawg/maskanya_privatekey`, `/etc/sysctl.d/99-maskanya-hardening.conf`

### MaskanyaHopMsk (Moscow, entry) — WIPE-FIRST

Arrived with ispmanager6-lite, BIND, MySQL, ProFTPD, PHP-FPM, nginx on :80 — a full web-hosting stack from provider's default image. Nothing of ours is there; a destructive wipe playbook (`playbooks/wipe-msk.yml`, typed "WIPE" confirmation + FirstVDS snapshot required) purges everything before the normal `common` role runs.

### DNS (already configured)

Cloudflare zone `animeenigma.ru`:
- `sub.maskanya.animeenigma.ru` → 103.137.249.134 (direct, no proxy)
- `maskanya.animeenigma.ru` → 103.137.249.134 (direct, no proxy)
- `panel.maskanya.animeenigma.ru` → CF-proxied (104.21.43.148) — fine because panel is mesh-only; if HTTP-01 fails behind the CF proxy during cert issuance, fall back to DNS-01 or temporarily disable the proxy for that one record

## Protocol Stack

### VLESS+Reality — Both Hops

- **Client → Entry:** VLESS+Reality with `xtls-rprx-vision` flow, per-node randomized SNI from neutral-country decoy pool
- **Entry → Exit:** VLESS+Reality with **empty `flow`** (Vision is a client-only optimization; using it on an intermediate hop breaks the chain), independently randomized SNI from the same pool (different decoy than the entry)

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

**Short IDs:** 8-hex per node, stored in host_vars; must match on both ends of each hop (client+inbound, entry-outbound+exit-inbound).

## Control Plane

### Marzban Panel

Open-source panel running on mgmt host (ZenithOfVastness). Provides:
- Multi-node support (gRPC/mTLS to each marzban-node agent — Phase 1.5)
- Per-user subscription URLs (clients fetch updated VLESS configs)
- Traffic quotas, user expiry dates
- REST API (future SaaS billing layer integrates here)
- Telegram bot integration

Database: MariaDB (production-grade, backed up nightly). Deployed as Docker Compose stack bound to `10.77.0.1:8000` (mesh-only). Subscription endpoint reached via a new vhost in the **existing** nginx (not a container nginx), same certbot HTTP-01 pattern as the other 13 vhosts.

### Subscription Model

- Each user gets one subscription URL: `https://sub.maskanya.animeenigma.ru/sub/{token}`
- Client (Hiddify, v2rayN, sing-box, Streisand) fetches the URL, receives one VLESS URI per chain the user is entitled to
- Adding a new entry/exit node → Marzban regenerates configs → users see the new chain on next subscription refresh
- Option 1 (now): explicit N×M chain list. Option 2 (later): smart chain recommendations with real-time ping tests.

**Phase-1 implementation note — marzban-node deferred:** Marzban's node agent replaces `config.json` on the node, which would clash with our Ansible-managed split-routing template. For Phase 1 we use **standalone Ansible-managed xray** on all nodes; Marzban handles user CRUD + subscription URL generation only. User UUIDs are SOPS-encrypted in inventory (`secrets/xray_clients.yml`) and templated directly into xray configs. Marzban panel's node registry mirrors what Ansible deploys so subscription URLs still render correctly. Migration to marzban-node is scheduled for **Phase 1.5** once we split the xray template into "Marzban-managed user DB" vs "Ansible-managed routing" layers.

### Service Model

Invite-only for now. Architecture is SaaS-ready from start — Marzban API supports future signup/billing/abuse layers without replacing the core.

## Networking

### AmneziaWG Control Mesh (not plain WireGuard)

WireGuard is blocked by Russian DPI. AmneziaWG is the Amnezia team's WG fork that injects randomized junk packets into handshakes, evading WG fingerprinting. Kernel module on Linux 5.10+, `awg`/`awg-quick` CLI.

- **Topology:** star, hub at mgmt (ZenithOfVastness)
- **Interface:** `awg1` on every host (ZOV already carries an unrelated `awg0` @ 10.0.0.10 from another project — `awg1` is namespaced so both coexist)
- **Listen port:** UDP **`51821`** (51820 taken by existing `awg0` on ZOV)
- **Subnet:** `10.77.0.0/24`
  - `10.77.0.1` — mgmt hub (ZenithOfVastness)
  - `10.77.0.10+` — entry nodes (MaskanyaHopMsk @ 10.77.0.10)
  - `10.77.0.50+` — exit nodes (MaskanyaExitKZ1 @ 10.77.0.50)
  - `10.77.0.100+` — operator laptops
- **Junk params** (`Jc/Jmin/Jmax/S1/S2/H1-H4`) defined once in Ansible `group_vars/all.yml`, identical across all peers
- **Carries:** Marzban gRPC (post-P1.5), Prometheus scrape, SSH admin, Loki push (future), Xray stats API
- **Does NOT carry:** user VPN traffic; entry→exit data traffic also goes over **public internet** wrapped in VLESS+Reality, not through the mesh. AWG is control-plane only.

Applied uniformly across the fleet so the hub speaks one protocol.

**Fallback path (documented, not built):** If AmneziaWG starts getting blocked, control channel moves inside a Reality-wrapped TCP tunnel via xray/gost. Same 10.77.0.0/24 addressing, only transport swaps.

### Admin Access

Operator laptop joins the AmneziaWG mesh. All admin surfaces (SSH from mesh only, Marzban UI, Grafana, Prometheus) bind to the mesh interface. No admin exposure on public internet.

### Public-Facing Surfaces

| Surface | Host | Port | Purpose |
|---|---|---|---|
| Reality VLESS | entries | `443/tcp` | user data plane ingress |
| Reality VLESS | exits (dedicated) | `443/tcp` | entry→exit data plane (source-IP allowlisted to entry WAN IPs) |
| Reality VLESS | exits (shared-use, ZOV) | **`8443/tcp`** | same role, alt port — ZOV's nginx owns `:443` for 13 unrelated vhosts |
| Subscription HTTPS | mgmt (ZOV) | `443/tcp` | `GET /sub/{token}` — new vhost inside existing nginx |
| Existing ZOV vhosts | mgmt (ZOV) | `443/tcp` | 13 unrelated services — untouched |
| AmneziaWG | all | **`51821/udp`** (iface `awg1`) | control mesh, peer-IP allowlisted |

Everything else is mesh-only.

### Domains & DNS

- **Base domain:** `maskanya.animeenigma.ru`
- **DNS:** Cloudflare, no proxy for data-plane records (CF not in data path); panel record is CF-proxied but serves a mesh-only UI
- **ACME:** Let's Encrypt via **HTTP-01** (Phase 1 — matches ZOV's existing certbot+nginx pattern; no Cloudflare API token required). **DNS-01** with scoped Cloudflare API token as fallback when HTTP-01 is not viable (CF-proxied records, wildcards).
- **Subdomains:**
  - `sub.maskanya.animeenigma.ru` — public subscription endpoint
  - `panel.maskanya.animeenigma.ru` — Marzban UI (mesh-only; public A record so LE can issue the cert)
  - `grafana.maskanya.animeenigma.ru` — Grafana (mesh-only, same pattern; added in Phase 2)

**TLD risk note:** `.ru` is Russian-jurisdiction — RKN can force-revoke. Mitigation: register a dormant backup domain on a foreign TLD (`.xyz`, `.li`, `.st`) pre-beta. Migration planned post-beta.

## Components per Host Type

### Entry Nodes (RU, minimal-footprint)

- `xray-core` installed as `/usr/local/bin/xray-maskanya`, systemd unit `xray-maskanya.service` (data plane: Reality inbound + outbound + split routing)
- `node_exporter` (Prometheus metrics via mesh)
- `amneziawg` client on interface `awg1`
- `chrony` (NTP — Reality rejects >60s clock skew)
- `unattended-upgrades`
- `journald` with `Storage=volatile`, size-capped — no persistent logs, no user IPs retained
- **Nothing else.** No panel, no DB, no Grafana, no certs, no state worth seizing.
- `marzban-node` agent — deferred to Phase 1.5 (see "Subscription Model")

### Exit Nodes (foreign)

- Same base as entry (xray-maskanya, node_exporter, AWG client, chrony, upgrades)
- No split routing — all non-private traffic egresses to internet via `freedom` outbound
- **Dedicated exit:** nftables default-drop; Reality `443` open only to entry WAN IPs (allowlist)
- **Shared-use exit (ZenithOfVastness):** additive iptables only; Reality on **`8443`** open only to entry WAN IPs; leaves nginx, Docker, existing awg0, fail2ban, x-ui untouched
- `marzban-node` agent — deferred to Phase 1.5

### Management Host (foreign, on ZenithOfVastness)

- `marzban` panel: Docker Compose (FastAPI + MariaDB), bound to `10.77.0.1:8000` (mesh only)
- Subscription endpoint: new vhost in **existing** nginx proxying to Marzban on mesh (not a new nginx container)
- `prometheus` + `grafana` + `loki` + `promtail` (Phase 2)
- `blackbox_exporter` (synthetic probes to each entry's public Reality port)
- `alertmanager` → Telegram bot
- `restic` (nightly encrypted backup to S3-compatible storage)
- `amneziawg` hub on interface `awg1`
- Admin SSH + panel UI behind mesh only; public surface = subscription endpoint + existing 13 unrelated vhosts + healthcheck

## Infrastructure as Code

### Ansible-Only (no Terraform)

Mixed VPS providers (RU: FirstVDS/Aeza/Timeweb, KZ: local, NL: various) without uniform TF support. Ansible owns the full lifecycle from a fresh SSH-able box. TF module for Hetzner exits can be layered later if needed.

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
│   │       │   ├── all.yml           # AWG junk params, decoy pool, versions, awg interface/port
│   │       │   ├── mgmt.yml
│   │       │   ├── entries.yml      # xray_role=entry, xray_inbound_port=443, journald volatile
│   │       │   └── exits.yml        # xray_role=exit, xray_inbound_port=8443 (default; dedicated exits override to 443)
│   │       └── host_vars/
│   │           ├── ZenithOfVastness.yml    # awg_role=hub, preserve_* flags, 10.77.0.1
│   │           ├── MaskanyaHopMsk.yml      # awg_role=spoke, xray_exit_targets, 10.77.0.10
│   │           └── MaskanyaExitKZ1.yml     # awg_role=spoke, dedicated 443, 10.77.0.50
│   ├── roles/
│   │   ├── common/          # ZOV-aware; every subsystem respects preserve_* flags
│   │   ├── firewall/        # divergent: nftables (dedicated) vs iptables-additive (shared-use)
│   │   ├── amneziawg/       # awg1 interface, UDP 51821
│   │   ├── node_exporter/
│   │   ├── xray_common/     # binary=xray-maskanya, unit=xray-maskanya.service
│   │   ├── xray_entry/      # Reality inbound 443 + Reality outbound to exits + split routing
│   │   ├── xray_exit/       # Reality inbound (8443 on ZOV, 443 elsewhere) + freedom outbound
│   │   ├── marzban_node/    # Phase 1.5, stub in Phase 1
│   │   ├── marzban_panel/   # Docker Compose + existing-nginx integration
│   │   ├── monitoring/      # Phase 2
│   │   └── backup/          # Phase 2
│   └── playbooks/
│       ├── site.yml
│       ├── bootstrap.yml
│       ├── wipe-msk.yml               # destructive, typed confirmation required
│       ├── add-entry-node.yml
│       ├── add-exit-node.yml
│       ├── rotate-reality-keys.yml
│       └── rotate-awg-keys.yml
├── secrets/
│   ├── marzban_admin.yml
│   ├── mariadb.yml
│   ├── cloudflare_api_token.yml       # Phase-2 only (HTTP-01 used in Phase 1)
│   ├── s3_backup_credentials.yml
│   ├── xray_clients.yml               # user UUIDs + shared chain UUIDs (Phase 1 only; migrates to Marzban in P1.5)
│   └── grafana_admin.yml
├── docs/
│   ├── superpowers/specs/
│   ├── runbooks/
│   └── architecture/adr/
├── scripts/
├── .github/workflows/
│   ├── lint.yml
│   └── validate.yml
├── .sops.yaml
├── .gitignore
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
- **Two-pass propagation:** first run generates keys, operator commits public keys to host_vars, second run templates dependents (peer lists, entry outbounds)

### Bootstrap Sequence (new node, ~10 min)

1. Order VPS, get root SSH + IP
2. Add SSH alias to `~/.ssh/config`
3. Append stub to `hosts.yml`, create `host_vars/<Name>.yml`
4. **If provider image is dirty (e.g. FirstVDS ispmanager):** take provider snapshot, run `make wipe-<name>` first
5. `make bootstrap HOST=<Name>` — hardening, admin user, baseline packages, AWG mesh join
6. Commit generated public keys (AWG, Reality) to `host_vars/` after the first run
7. `make add-entry HOST=<Name>` (or `add-exit`) — role-specific stack, Marzban registration
8. Marzban regenerates configs; clients see new chain on next subscription refresh

### CI — GitHub Actions

- `ansible-lint` + `yamllint` + `shellcheck`
- `sops --decrypt` smoke test
- `ansible-playbook --syntax-check` on all playbooks
- `ansible-playbook --check --diff` against mock inventory (post-Phase-1)
- Block merge on red

### Makefile

Operator UX — single commands: `make lint`, `make syntax-check`, `make apply`, `make bootstrap HOST=…`, `make add-entry HOST=…`, `make add-exit HOST=…`, `make rotate-reality-keys`, `make rotate-awg-keys`, `make wipe-msk`.

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
| `/etc` on mgmt (Maskanya-owned paths only) | mgmt | same | same |
| Grafana dashboards | git | git history | — |
| Ansible inventory + SOPS | git | git provider | — |

### What We Do NOT Back Up

- Reality private keys (regenerate on rebuild — one chain offline until users refetch subscription)
- AmneziaWG private keys (regenerate + re-peer)
- Prometheus/Loki data (ephemeral)
- RU entry node OS state (full rebuild <10min via Ansible)
- Other-projects state on ZOV (kino-site, gitea, animeenigma-saas-* Docker volumes, etc.) — user's existing responsibility, not Maskanya's

### Mechanics

- restic → S3-compatible storage (Scaleway/Wasabi/Selectel — operator picks), nightly via systemd timer
- Stale-backup alert if snapshot > 48h
- Restore drill: quarterly, runbook-driven, tested on throwaway VPS

## Security

### Per-Host Hardening (via `common` role)

- SSH: port 22 (OpenSSH default — reliability over obscurity), key-only, no root, `MaxAuthTries 3`. Security is enforced by pubkey-only auth + fail2ban, not port change. Port-change attempts on Ubuntu 22.10+ require disabling `ssh.socket` and add fragility with no real gain.
- `unattended-upgrades` with auto-reboot in maintenance window (03:00 local, jittered)
- `fail2ban` on mgmt for subscription endpoint (rate-limit 404 tokens) — on ZOV use the **existing** fail2ban install; add our jail, don't reinstall
- `chrony` for time sync on dedicated Maskanya nodes only; **preserve ZOV's existing systemd-timesyncd**
- Kernel sysctl hardening via namespaced `/etc/sysctl.d/99-maskanya-hardening.conf`: `net.ipv4.conf.all.rp_filter=1`, `accept_source_route=0`, `tcp_syncookies=1`. **Do NOT set `ip_forward`** — xray is application-layer; on ZOV let Docker manage whatever it needs.
- **Firewall:** divergent per host. Dedicated Maskanya nodes run **nftables** (default-drop INPUT). Shared-use hosts (ZenithOfVastness) with existing Docker/container workloads run an **additive `iptables` shell script** managed by a systemd oneshot unit — installing nftables would fight Docker's iptables chains and break container networking.

### Firewall per Role

- **Entry (dedicated, nftables):** `443/tcp` from anywhere; AWG `51821/udp` from hub peer only; SSH `22/tcp` public (pubkey-only + fail2ban; tighten to `ip saddr {{ awg_subnet }}` once operator laptop is a stable peer); node_exporter `9100/tcp` bound to mesh IP; drop else
- **Exit (dedicated, nftables):** `443/tcp` from entry WAN IPs only (allowlist); AWG from hub; SSH `22/tcp` public (same pubkey-only + fail2ban); drop else
- **Exit (shared-use — ZenithOfVastness, iptables-additive):** append INPUT rules via `iptables -C … || iptables -A …` (idempotent) for `8443/tcp` (Reality from entry WAN IPs only) and `51821/udp` (AWG from entry WAN IPs only); leave DOCKER, DOCKER-USER, f2b-sshd, and any other existing chains untouched; no flushes, no policy changes
- **Mgmt (same host as shared-use exit):** Marzban + Grafana vhosts in existing nginx bound to mesh IP; subscription vhost publicly reachable on existing `:443`; nothing else exposed

### Incident Response (documented in runbooks)

1. **RU entry seized:** rotate Reality keys, remove from inventory, Marzban re-issues configs. Users pick another chain.
2. **Mgmt compromised:** rotate all secrets, restore DB from backup onto fresh host, re-issue subscription URLs.
3. **Age key compromised:** rotate SOPS recipients, re-encrypt all secrets, revoke key.
4. **User token leaked:** rotate single user's Marzban subscription token.
5. **ZOV baggage broken by Maskanya change:** revert via Ansible (roles are idempotent) + restore from restic; the preservation tests in CI should catch most regressions pre-merge.

## Phasing

### Phase 1 — Foundation (mgmt + first chain)

**Goal:** One working chain `MaskanyaHopMsk → ZenithOfVastness`, one user connects, existing ZOV services untouched.

0. **MaskanyaHopMsk wipe** (destructive, one-time): purge ispmanager/BIND/MySQL/ProFTPD/PHP/nginx from provider image. Typed "WIPE" confirmation + FirstVDS snapshot required. Runs once, then excluded from regular `site.yml` convergence.
1. Repo scaffold: Ansible layout, SOPS, CI, Makefile
2. `common` role: SSH hardening, admin user, unattended-upgrades, sysctl hardening, chrony (on MSK only) — **ZOV-aware** (preserves existing timesyncd, fail2ban, nginx, awg0, Docker via `preserve_*` host_vars flags)
3. `amneziawg` role: star mesh on interface `awg1` / UDP `51821` — ZOV hub @ 10.77.0.1 ↔ MSK spoke @ 10.77.0.10 + operator laptop; coexists with ZOV's existing awg0
4. `firewall` role: **divergent** — nftables default-drop on MSK, additive iptables shell script + systemd oneshot on ZOV
5. `xray_common` role: install `xray-maskanya` binary + geoip/geosite, generate Reality keypair
6. `xray_exit` role on ZenithOfVastness: Reality inbound on **`8443`** (alt port; `443` owned by existing nginx), freedom outbound
7. `xray_entry` role on MaskanyaHopMsk: Reality inbound on 443, Reality outbound to **ZOV public IP:8443** (over public internet, NOT mesh) with empty `flow` (Vision is client→entry only), `geoip:ru` + `geosite:category-ru` → direct egress
8. `marzban_panel` role on ZenithOfVastness: Docker Compose (Marzban + MariaDB) bound to `10.77.0.1:8000`; subscription endpoint integrated as new vhost in existing nginx; certbot HTTP-01 for `sub.maskanya.animeenigma.ru` and `panel.maskanya.animeenigma.ru`
9. **marzban-node deferred** to Phase 1.5 — standalone Ansible-managed xray handles routing; Marzban handles user CRUD + subscription URL generation; user UUIDs SOPS-encrypted in `secrets/xray_clients.yml`
10. Create test user (via Marzban UI from mesh), fetch subscription URL, connect from RU client (Hiddify)
11. Verify: `youtube.com` via NL (`curl ifconfig.me` returns 103.137.249.134), `yandex.ru` via MSK direct (`tcpdump` on MSK WAN shows direct egress, no ZOV hop), all 13 pre-existing nginx vhosts on ZOV still responding, `docker ps` diff pre/post == 0

**Exit criterion:** Human connects from Russia, foreign + domestic sites route correctly, zero regressions on ZOV's existing services.

### Phase 1.5 — marzban-node integration (optional, between Phase 1 and 2)

**Goal:** Replace Ansible-templated xray config with marzban-node agent that pulls users from panel, WITHOUT losing the split-routing rules.

1. Split xray template responsibility: Marzban manages `inbounds[].clients[]`; Ansible manages `routing.rules` (split routing) via a patch overlay or post-processing hook
2. Deploy marzban-node on MSK and ZOV (gRPC/mTLS to panel)
3. Cut over chain-by-chain; verify split routing still intact after agent takes over
4. Decommission `secrets/xray_clients.yml` (Marzban becomes source of truth for users)

**Exit criterion:** Adding a user via Marzban UI propagates to xray without any git commit or Ansible run.

### Phase 2 — Observability + Backups

**Goal:** Monitor the fleet and recover from disaster.

1. `node_exporter` on all hosts (bind to mesh IP only)
2. `monitoring` role: Prometheus + Grafana + Loki + blackbox_exporter — deployed as a Docker Compose stack on ZOV, all bound to `10.77.0.1`, grafana vhost in existing nginx
3. Grafana dashboards committed as JSON
4. Alertmanager → Telegram bot
5. `backup` role: restic → S3 nightly (Maskanya-owned paths only; other-projects state on ZOV excluded)
6. Restore runbook tested on throwaway VPS

**Exit criterion:** Grafana shows green fleet, Telegram fires test alert, restic restore produces working Marzban.

### Phase 3 — Second Exit + Fleet Scaling

**Goal:** Multi-exit works, adding a node is one command.

1. Onboard MaskanyaExitKZ1 (dedicated exit, Reality on `443`): bootstrap → AWG → xray_exit
2. Chain `msk-kz` visible in subscriptions alongside `msk-nl`
3. Verify both chains work concurrently
4. Test `add-entry-node.yml` with throwaway RU VPS
5. Test `add-exit-node.yml` similarly
6. Test key rotation playbooks end-to-end (Reality + AWG separately)
7. CI validated: lint → syntax-check → dry-run passes on PR

**Exit criterion:** `make add-entry HOST=TestNode` takes fresh VPS to live in <10 minutes.

### Post-Beta Backlog

- Dedicated mgmt host (lift off ZenithOfVastness)
- Backup domain migration (off `.ru` TLD)
- Smart chain recommendations (real-time ping tests)
- Self-serve SaaS: signup, billing, abuse handling
- AmneziaWG fallback transport (Reality-wrapped control tunnel)
