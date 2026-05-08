# Channel A PoC — VLESS+Reality+XHTTP+Vision

**What this tests:** Whether the May 2026 hardened VLESS stack (XHTTP transport, stream-one mode, chrome uTLS fingerprint, Yandex CDN SNI) actually survives current RU DPI when running on our existing servers.

**Servers:** uses live `ZenithOfVastness` (NL) and `MaskanyaHopMsk` (MSK).
- **MSK :443** — standard HTTPS port. MSK is post-wipe so `:443` is free.
- **ZOV :2053** — alt-HTTPS port (Cloudflare-supported, used by legitimate services). Avoids `:443` (13 production nginx vhosts) and `:8443` (existing `xray-maskanya`). Habr's "non-standard ports get banned" warning targets `:1337/:1984/:8080/:47000`-style outliers; `:2053` is a recognised HTTPS alternative and not in that risk class.

**Topology:**
```
RU client → MSK :443 (xray-poc, Reality+XHTTP+Vision in)
            └─→ Reality+XHTTP out → ZOV :2053 (xray-poc, Reality+XHTTP in)
                                    └─→ freedom out → internet
```

## Prerequisites

- SSH access to both hosts (`ZenithOfVastness` and `MaskanyaHopMsk` aliases in `~/.ssh/config`).
- v2rayN ≥ 6.46 (Windows), or NekoRay ≥ 3.27, or any client with XHTTP + stream-one support.
- `curl`, `wget`, `jq` locally.

## Step-by-step

### 1. Generate Reality keypair on ZOV (one-time)

```bash
# Run on your laptop. Pulls a temporary xray binary onto ZOV, generates keys, prints them.
./scripts/keygen.sh
```

This prints something like:
```
ZOV_REALITY_PRIVATE_KEY=YJk...
ZOV_REALITY_PUBLIC_KEY=Zr1...
ZOV_SHORT_ID=a3f9b2c8
CHAIN_UUID=11111111-2222-3333-4444-555555555555
USER_UUID=99999999-8888-7777-6666-555555555555
```

Save these — `scripts/render.sh` consumes them as env vars.

### 2. Render configs

```bash
export ZOV_REALITY_PRIVATE_KEY=...
export ZOV_REALITY_PUBLIC_KEY=...
export ZOV_SHORT_ID=...
export CHAIN_UUID=...
export USER_UUID=...

./scripts/render.sh
```

Writes `configs/zov-rendered.json` and `configs/msk-rendered.json`.

### 3. Deploy

```bash
./scripts/deploy.sh
```

This does:
- `scp` xray binary + rendered config to ZOV under `/opt/xray-poc/`, installs `xray-poc.service`, starts it on `:2053`
- adds an iptables ACCEPT rule on ZOV for `:2053` from MSK's WAN (82.146.35.191) — does NOT open it to the world; PoC traffic is MSK→ZOV-only
- same on MSK under `/opt/xray-poc/` listening on `:443` from world (so RU client can reach it)

Idempotent: re-running it overwrites configs and restarts services.

### 4. Generate client URI

```bash
./scripts/gen-client-uri.sh
```

Prints:
```
vless://<USER_UUID>@82.146.35.191:443
  ?type=xhttp
  &mode=stream-one
  &path=/poc
  &security=reality
  &pbk=<MSK_REALITY_PUBLIC_KEY>
  &sid=<MSK_SHORT_ID>
  &sni=storage.yandex.net
  &fp=chrome
  &flow=xtls-rprx-vision
#Maskanya-PoC-A
```

(URL-encoded for paste into v2rayN.)

### 5. Test

From a Russian network:
1. Paste URI into v2rayN.
2. Set system proxy or v2rayN's "Mode → Global mode".
3. `curl ifconfig.me` should return `103.137.249.134` (ZOV NL).
4. Browse some sites for 5 minutes — watch for the 30-second-then-dies pattern that signals the 16KB classifier.

If it dies after a while:
- Try changing SNI in URI to one of: `yastatic.net`, `avatars.mds.yandex.net`, `userapi.com`, `vkuser.net`. Re-render configs to match (`reality_sni` env var).
- Try without Vision: change client URI `&flow=` to empty and switch xhttp mode to `auto` on both ends. Re-deploy.

### 6. Tear down (when done)

```bash
./scripts/teardown.sh
```

Stops + removes `xray-poc.service`, `/opt/xray-poc/`, and the iptables rule on both hosts.

## Files

- `configs/zov.json.tmpl` — xray config template, exit side
- `configs/msk.json.tmpl` — xray config template, entry side
- `scripts/keygen.sh` — generates Reality + UUID set
- `scripts/render.sh` — fills templates with env vars → `configs/*-rendered.json`
- `scripts/deploy.sh` — pushes binary + config + systemd unit + iptables rule to both hosts
- `scripts/gen-client-uri.sh` — emits client URI string
- `scripts/teardown.sh` — undeploys

## Known caveats

- **xray version:** scripts pull `Xray-linux-64.zip` from upstream releases (latest). XHTTP+stream-one needs ≥ v25.x. If upstream renames the asset, edit `XRAY_VERSION` in `deploy.sh`.
- **MSK :443 collision:** post-wipe MSK should have `:443` free, but verify with `ss -tlnp | grep :443` before deploy. If something else has bound it (rarely, ssh.socket on weird configs, or leftover nginx from ispmanager wipe), stop it first.
- **MSK iptables:** existing nftables (from the `firewall` Ansible role) may already restrict :443. The deploy script adds an additive rule; if the role re-runs, it may stomp the rule. Don't run `make apply` while testing.
- **ZOV preservation contract:** `:2053` on ZOV's WAN is currently free (existing services use 22, 80, 443, 8443, 51820). If the host_vars allowlist for the production xray exit changes, this PoC port may need re-checking.
- **`storage.yandex.net` as `dest:`:** Yandex CDN is reliably reachable from any RU host at the time of writing. If it gets fenced for some reason, fall back to `yastatic.net`.
