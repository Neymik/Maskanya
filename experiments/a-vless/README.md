# Channel A PoC — single-hop VLESS+Reality+XHTTP

**What this tests:** the single high-stakes question — does the May 2026 hardened VLESS stack (XHTTP transport, stream-one mode, chrome uTLS fingerprint, Yandex CDN SNI as Reality dest, per-user shortIds) actually pass current RU DPI when listening on `:443`?

**Why single-hop:** anything other than `:22 / :80 / :443` on either host is at risk under the May 2026 regime. ZOV's `:443` is occupied by 13 production vhosts; making it shareable requires the `nginx_stream` SNI demuxer described in the spec — that's Phase 1 work, not PoC scope. So the PoC tests **just the client→MSK leg** which is the genuinely uncertain part. If it works, MSK→ZOV chain (over Reality+XHTTP+`:443` via the demuxer) is a Phase 1 task with very low residual risk.

**Topology:**
```
RU client → MSK :443 (xray-poc, Reality+XHTTP+Vision in)
            └─→ MSK freedom out (direct egress) → internet
```

Success: from a RU network, `curl ifconfig.me` through the tunnel returns `82.146.35.191` (MSK's own IP). That's not the production target IP — but it proves the tunnel is live and DPI is letting our handshake through. If this works, Channel A is alive on the protocol level; multihop wiring becomes a configuration concern.

**Servers:** uses live `MaskanyaHopMsk` only. ZOV is untouched.

## Prerequisites

- SSH access to `MaskanyaHopMsk` (`~/.ssh/config` alias).
- v2rayN ≥ 6.46 (Windows), or NekoRay ≥ 3.27, or any client with XHTTP + stream-one support.
- `curl`, `wget`, `unzip`, `openssl`, `uuidgen`, `envsubst` locally (all standard on macOS/Linux).

## Step-by-step

### 1. Generate Reality keypair + UUID

```bash
./scripts/keygen.sh > .env.poc-a
source .env.poc-a
```

### 2. Render config

```bash
./scripts/render.sh
```

Writes `configs/msk-rendered.json`.

### 3. Deploy to MSK

```bash
./scripts/deploy.sh
```

Pre-flight: aborts if `:443` on MSK is already bound (rarely happens post-wipe — but ssh.socket on Ubuntu 22.10+, leftover nginx from ispmanager, etc., are possible).

What it does:
- Downloads xray v25.5.5 (configurable via `XRAY_VERSION` env).
- `scp` binary + config to `/opt/xray-poc/` on MSK.
- Installs `xray-poc.service` with `CAP_NET_BIND_SERVICE` (xray binds `:443` without running as root).
- Adds `iptables -I INPUT -p tcp --dport 443 -j ACCEPT` (additive; idempotent).
- Starts the service.

### 4. Generate client URI

```bash
./scripts/gen-client-uri.sh
```

Prints:
```
vless://<USER_UUID>@82.146.35.191:443
  ?type=xhttp&mode=stream-one&path=%2Fpoc
  &security=reality
  &pbk=<MSK_REALITY_PUBLIC_KEY>&sid=<MSK_SHORT_ID>
  &sni=storage.yandex.net&fp=chrome
  &flow=xtls-rprx-vision
#Maskanya-PoC-A
```

### 5. Test

From a Russian network:
1. Paste URI into v2rayN.
2. Set v2rayN's "Mode → Global mode" or use system proxy.
3. `curl ifconfig.me` → should return `82.146.35.191` (MSK IP).
4. Browse for 5+ minutes — watch for the "works for 30s then dies" pattern that signals the 16KB-payload classifier.

### Reading the results

| Result | Meaning | Next step |
|---|---|---|
| `ifconfig.me` returns `82.146.35.191` | tunnel is alive — Reality+XHTTP+chrome+yandex SNI passes RU DPI | proceed to Phase 1 (nginx SNI demuxer + ZOV-side xray) |
| TCP RST during handshake | DPI is fingerprinting the handshake itself | try alternative SNI; if still fails, Channel A is non-viable in this regime — go to Channel C/B |
| Connection completes, no data flows | behavioural classifier is killing the payload | try `mode: "auto"` (drop Vision); try other Yandex SNIs |
| Works for 30 seconds then dies | payload-size classifier (~16KB threshold) | tweak `xPaddingBytes`, possibly drop XHTTP `mode: stream-one` for `auto` |
| Works inconsistently across networks | ISP-specific TSPU behaviour | document which carriers work; collect tcpdump from problem ISPs |

If it dies after a while:
- Try other SNIs in `configs/msk.json.tmpl` and re-render: `yastatic.net`, `avatars.mds.yandex.net`, `userapi.com`, `vkuser.net`. Re-run `render.sh` + `deploy.sh`.
- Try without Vision: change `flow` in template to `""` and `mode` to `"auto"`. Re-deploy. If this works but the Vision config didn't, Vision is the trigger.

Capture pcap from the RU side for ~60s during testing for later forensics:
```bash
sudo tcpdump -i any -w channel-a-test.pcap host 82.146.35.191 and tcp port 443
```

### 6. Tear down

```bash
./scripts/teardown.sh
```

Stops + removes `xray-poc.service`, `/opt/xray-poc/`, and the `:443` iptables rule on MSK.

## Files

- `configs/msk.json.tmpl` — xray config template, single-hop entry-side
- `scripts/keygen.sh` — generates Reality keypair + UUID + short ID
- `scripts/render.sh` — fills template via envsubst → `configs/msk-rendered.json`
- `scripts/deploy.sh` — pushes binary + config + systemd unit + iptables rule to MSK
- `scripts/gen-client-uri.sh` — emits client URI string
- `scripts/teardown.sh` — undeploys

## Known caveats

- **Port discipline:** `:443` is the only RU-facing port we use. The earlier draft of this PoC used `:8446`/`:2053`; both ruled out under the "any port ≠ 22/80/443 is suspicious" rule.
- **xray version:** scripts pull `Xray-linux-64.zip` from upstream. XHTTP+stream-one needs ≥ v25.x. If upstream renames the asset, edit `XRAY_VERSION` in `deploy.sh`.
- **MSK iptables:** existing nftables (from the `firewall` Ansible role) may already restrict `:443`. The deploy script adds an additive rule; if the role re-runs, it may stomp the rule. Don't run `make apply` while testing.
- **MSK :443 collision:** post-wipe MSK should have `:443` free, but `deploy.sh` checks with `ss -tlnp` and aborts if not. If aborted, kill the listener manually and re-run.
- **`storage.yandex.net` as `dest:`:** Yandex CDN is reliably reachable from any RU host at the time of writing. If it gets fenced, fall back to `yastatic.net`.
- **No multihop in this PoC:** MSK exits directly to the internet. `ifconfig.me` returns the MSK IP, not a foreign one. That's fine — this PoC tests DPI bypass, not exit-IP geography. ZOV exit goes live in Phase 1.
