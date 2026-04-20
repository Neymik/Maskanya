---
name: ZOV bootstrap progress snapshot (2026-04-20)
description: site.yml converged on ZenithOfVastness from the ZOV-hosted controller. Full fleet (minus MSK, which is down) is running. Remaining work is MSK rebuild + key crossover.
type: project
originSessionId: 5bd3f002-7d18-4791-9ae4-1374ec8eefb6
---
**Status as of 2026-04-20:** Controller has been migrated onto ZenithOfVastness at `/data/maskanya/`. `ansible-playbook site.yml --limit ZenithOfVastness` converges **fully green** (ok=67, failed=0, idempotent dry-run: changed=0). Marzban panel stack is up on mesh, LE certs issued for both public vhosts, xray Reality inbound is listening on **:8444**, AmneziaWG hub awg1 is up on 10.77.0.1 / UDP 51821.

**Why:** ZOV is standing in as mgmt + test exit while MSK is rebuilt. With the controller on ZOV, the laptop is no longer an SPOF and we can validate the exit + panel stack before MSK comes back online.

**How to apply next session:**

1. `export SOPS_AGE_KEY_FILE=/root/.config/sops/age/maskanya.txt` (already on ZOV, mode 0600).
2. From `/data/maskanya`: `make apply` runs the full fleet; `ansible-playbook -i inventory/production/hosts.yml playbooks/site.yml --limit <host>` for a single host.
3. Ansible itself is installed via the ansible PPA (`ansible 10.7.0 / core 2.17.14`) — Ubuntu jammy's 2.10 is too old for the vendored collections (community.general 12.x requires core ≥2.15). sops 3.9.2 and age 1.0.0 are installed via apt + GitHub release.
4. ZenithOfVastness uses `ansible_connection: local` in host_vars (controller lives on the target).

**What's converged on ZOV:**
- `/data/maskanya-management` project root (mode 0750)
- Namespaced sysctl drop-in, baseline packages, unattended-upgrades
- Additive iptables rules: TCP 8444 from 82.146.35.191, UDP 51821 from entry/exit peer IPs
- awg1 up on 10.77.0.1 with ListenPort 51821 (no MSK peer yet — MSK pubkey pending)
- `/etc/amnezia/amneziawg/awg1.conf` deployed (package-expected path)
- node_exporter on mesh IP :9100
- xray-maskanya binary at `/usr/local/bin/xray-maskanya`, geoip/geosite at `/usr/local/share/xray-maskanya/`, systemd unit sets `XRAY_LOCATION_ASSET` to that dir
- xray-maskanya.service active, Reality inbound on 0.0.0.0:8444 (reality_public_key: `aiVYxkLAcaCrBgo1UwyRvg-nk1I5kmC8FHOMl5qqBj0`, committed)
- AWG hub public key: `ZQWEAZq9GlYva3mYZWBoVI41qXsg22p7lnTlGFWmFzg=` (committed)
- Marzban compose stack: `marzban-marzban-1`, `marzban-mariadb-1` up; API 200 on `http://10.77.0.1:8000/docs`
- nginx vhosts `maskanya-sub` + `maskanya-panel` live with LE certs for `sub.maskanya.animeenigma.ru` + `panel.maskanya.animeenigma.ru`

**Uncommitted code fixes on the ZOV repo (migration + convergence):**
- `ansible/roles/amneziawg/defaults/main.yml` — `awg_config_dir: /etc/amnezia/amneziawg` (package expects this, not `/etc/amneziawg/`)
- `ansible/roles/amneziawg/tasks/install.yml` — uses `{{ awg_config_dir }}`
- `ansible/playbooks/rotate-awg-keys.yml` — default paths updated to `/etc/amnezia/amneziawg/...`
- `ansible/roles/xray_common/defaults/main.yml` — `xray_sha256` corrected to real v1.8.24 SHA256
- `ansible/roles/xray_common/tasks/reality_keygen.yml` — added `executable: /bin/bash` (Ubuntu /bin/sh is dash)
- `ansible/roles/xray_common/templates/xray-maskanya.service.j2` — added `Environment=XRAY_LOCATION_ASSET={{ xray_share_dir }}` so xray finds geoip.dat at runtime
- `ansible/roles/xray_exit/tasks/main.yml` — validate command wraps xray with `env XRAY_LOCATION_ASSET=…` so template validation succeeds at render time
- `ansible/roles/xray_entry/tasks/main.yml` — same `env XRAY_LOCATION_ASSET=…` wrap
- `ansible/roles/marzban_panel/defaults/main.yml` — `docker_compose_version: v2.30.3`
- `ansible/roles/marzban_panel/tasks/compose.yml` — installs Docker Compose V2 CLI plugin on-demand (ZOV uses Ubuntu's docker.io, which doesn't ship the plugin); health check switched from `/api/system` (dropped upstream) to `/docs` (stable unauthenticated probe)
- `ansible/roles/marzban_panel/tasks/nginx_integration.yml` — certbot tasks now retry for up to ~2 min when certbot.timer holds the lockfile
- `ansible/inventory/production/group_vars/all.yml` — `preserve_ssh`, `preserve_admin_user` defaults + `maskanya_project_root: /opt/maskanya` default
- `ansible/inventory/production/group_vars/mgmt.yml` — `marzban_install_dir` uses `{{ maskanya_project_root }}/marzban`
- `ansible/inventory/production/host_vars/ZenithOfVastness.yml` — `ansible_connection: local`, `ansible_user: root`, `preserve_ssh=true`, `preserve_admin_user=true`, `maskanya_project_root=/data/maskanya-management`, `xray_inbound_port=8444`, `awg_public_key` + `reality_public_key` populated
- `ansible/roles/common/tasks/main.yml` — gates `user.yml` and `ssh.yml` on `preserve_*`; adds project-root dir creation

**Outstanding for MSK rebuild:**
- Stand up MaskanyaHopMsk (apply `bootstrap.yml` then `site.yml --limit MaskanyaHopMsk`). This will generate MSK's AWG + Reality keypairs; commit MSK's `awg_public_key` to its host_vars so ZOV's `awg_peers` can template it, and add MSK's `reality_public_key` to ZOV's `xray_exit_targets` if we later use ZOV as an entry (not currently).
- After MSK comes up, run `site.yml` (no limit) once so both hubs learn each other's pubkeys via host_vars (two-pass convergence pattern described in `site.yml` header).

**ZOV preservation contract (must keep holding):**
- All 20 existing Docker containers still running
- 13 production nginx vhosts on :80/:443 untouched
- Existing `awg-quick@awg0` service still active on UDP 51820
- fail2ban + systemd-timesyncd + x-ui's xray at `/usr/local/x-ui/xray-linux-amd64` not modified
- **`mtg` (MTProto Telegram proxy) at `/usr/local/bin/mtg` still owns TCP :8443** — this is why Maskanya's Reality inbound runs on :8444 on ZOV (committed in host_vars). The firewall role is additive-only, so a stale `-A INPUT … --dport 8443 --comment maskanya-reality` rule was manually removed with `iptables -D …` after the port change; re-running the playbook won't re-add it.
- `preserve_*` flags in `host_vars/ZenithOfVastness.yml` enforce this (ssh, admin_user, nginx, iptables, awg0, timesyncd, fail2ban, docker, x_ui, journald all = true)
- `ansible_user: root` for ZOV (preexisting root pubkey access — do NOT create a parallel admin user)
