# Maskanya — project notes for Claude Code

Ansible-managed VLESS+Reality multihop VPN. Two nodes in production, controller runs
on the exit/mgmt host itself (`ansible_connection: local` for that host).

All host-specific facts (IPs, ports, SNIs, peer keys, mesh addressing) live in
`ansible/inventory/production/host_vars/` and `group_vars/`. Read those, don't
hardcode anything here.

## Topology

- **Entry node (RU)** — dedicated. Client → entry on VLESS+Reality+Vision.
  Wiped clean by `playbooks/wipe-msk.yml`.
- **Exit + mgmt node (NL)** — shared-use. Reality inbound on a non-`:443`
  port (the default `:443` and `:8443` are already taken by unrelated
  services on that box). Also runs the Marzban panel, the controller, and
  unrelated containers — every role honours the `preserve_*` flags on that
  host.
- **Control-plane mesh** (AmneziaWG on `awg1`) — control only, no user
  traffic. The host's own unrelated `awg0` stays untouched. Subnet + port
  live in inventory.

## Current DPI status — Russian ISPs easily block this stack (2026-04)

**As of April 2026 the current Maskanya stack (VLESS+Reality, Vision flow,
multihop entry→exit) is effectively blocked by Russian wireline carriers for
any non-trivial flow.** Treat the fleet as *degraded against its primary
threat model*, not operational. Small probes (2ip.ru, quick curls) still
pass and return the exit IP, which makes the service look healthy — but any
heavier page (news, video, long articles) freezes mid-load. Don't mistake a
successful 2ip.ru check for a working VPN.

Dominant detector driving this: **"15–20 KB freeze"** — TSPU pattern active
since Dec 2025 on TCP/443 TLS 1.3. Once a single connection's server→client
byte count exceeds ~15–20 KB, the carrier silently black-holes the rest
(no RST, no ICMP — just dead bytes). This targets the transport envelope,
not Reality's fingerprint, so SNI swaps and Xray upgrades only blunt it;
they don't bypass it. Multihop doesn't help because the detector sits on
the client→entry leg, before the hop into the mesh.

Stage A mitigation deployed 2026-04-21: Xray 1.8.24 → 25.12.8 fleet-wide,
entry + exit SNIs re-pointed to RU-plausible CDN domains, decoy pool
augmented. UUIDs + Reality keys unchanged. Current SNI choices are in
host_vars — do not duplicate them elsewhere. This is a stopgap: it buys
fingerprint plausibility and picks up upstream Reality tweaks, but does
*not* change the transport envelope the detector keys on.

Stage B is documented in the plan file under `/root/.claude/plans/` (not in
the repo) and is the real fix if Stage A falls short: secondary
VLESS+Reality+**XHTTP** inbound with a distinct SNI + shortId. XHTTP chunks
the stream so the 15–20 KB single-connection counter never trips —
attacking the detector at transport level rather than fingerprint level.
Expect Stage B to be necessary, not optional, for sustained RU wireline
use.

Chain-compartmentalization rule from the spec: entry SNI and exit SNI on
the same chain MUST differ. Check both sides of host_vars before pinning.

## Secrets — SOPS + age

The age key file path is set via `SOPS_AGE_KEY_FILE` in the operator's
environment and must be exported in every shell that runs `ansible-playbook`
or `sops -d`. Without it, template tasks that pull from
`secrets/xray_clients.yml` fail with `CouldNotRetrieveKey`, and the
xray_exit role's `no_log: true` hides the real error. If a render step fails
opaquely, re-run with the env var set before assuming anything deeper is
wrong.

Sensitive material under `secrets/` (`xray_clients.yml`, `mariadb.yml`,
`marzban_admin.yml`, `s3_backup_credentials.yml`) is SOPS-encrypted in the
repo. Never paste decrypted contents into chat, diffs, logs, or commits.
Reality private keys, client UUIDs, panel admin creds, and operator peer
addresses all count as credentials.

## Playbook run gate

Running `site.yml` (or any playbook) against the production hosts requires
explicit user approval per invocation. Don't chain runs silently. Expect the
first call each session to be blocked by the permission hook.

## Ansible check-mode caveat

`ansible-playbook ... --check --diff` fails at `Extract xray zip` because
`file: state=directory` doesn't materialize the dir in check mode and the
subsequent `unarchive` bails. This is an Ansible artifact, not a real drift —
skip check mode and go straight to apply when the diff surface is understood.

## Phase gate

Phase 1 only: xray clients live in `secrets/xray_clients.yml`, URIs are
hand-generated from host_vars + that file. Marzban is decorative — its
default subscription is **not** wired to the standalone xray service. Don't
hand users Marzban-generated links until Phase 1.5 absorbs user management.

## Operator commands

`make apply | bootstrap HOST= | rotate-reality-keys | rotate-awg-keys | wipe-msk`
— see `Makefile`. Never run `wipe-msk` without explicit ask; it's
destructive.
