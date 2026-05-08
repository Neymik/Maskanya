# Maskanya — Three-Channel PoC

Minimal proof-of-concept for the three channels in the [2026-05-08 design spec](../docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md). Goal: answer "does this approach actually work in the May 2026 RU regime" before investing in Ansible roles, Marzban integration, or a companion app.

**Scope per channel:** the smallest thing that produces a yes/no answer.

| Channel | What this tests | Effort |
|---|---|---|
| A — VLESS+Reality+XHTTP | Does xray-core 25.x with stream-one + chrome fp + Yandex CDN SNI survive RU DPI when run on FirstVDS? | ~2h, real deploy |
| C — YC Function | Can a function on `functions.yandexcloud.net` be reached from RU AND reach foreign IPs? | ~1h, requires YC account |
| B — WebRTC | Does WebRTC DataChannel work in a Russian browser at all? Loopback test only. | ~5min, browser only |

**What's deliberately out of scope:**
- Marzban integration → hardcoded UUIDs, manual config
- Ansible roles → bash scripts and SSH
- Companion app → use v2rayN / curl / browser
- TLS certs from LE → Reality steals real Yandex/Cloudflare cert; YC function uses YC-managed TLS
- Auto-failover, JWT auth, quota → not tested at PoC stage
- Production safety → this runs on different ports than `xray-maskanya`; if the PoC config breaks, production is unaffected

## Order to run

1. **Channel A first.** It's the primary path; if it works the rest is gravy. ~2 hours, you do this on the actual servers.
2. **Channel B in 5 minutes.** Just open the HTML in a Russian browser. Quick yes/no on whether WebRTC is even available before you invest in Channel B implementation later.
3. **Channel C if you have a YC account.** Skip if not — we can spin one up later.

## Channel A — see `a-vless/README.md`
## Channel B — see `b-webrtc/README.md`
## Channel C — see `c-yc-function/README.md`

## What "it works" means

For each channel, success = a Russian client can `curl https://ifconfig.me` through the channel and get back ZOV's NL IP (`103.137.249.134`) instead of the client's RU IP. That's the bar.

Failure modes to log when reporting:
- TCP RST during handshake → DPI is killing it at L7
- TCP timeout → likely L3 drop or ISP-level block
- Handshake completes but no data flows → behavioral classifier or RST-on-payload
- Works for 30s then dies → 16KB-threshold-style trigger
- Works inconsistently across networks → ISP-specific TSPU configuration

Capture `tcpdump -i any -w channel-X.pcap host <server-ip>` from the RU side for ~60s of testing. Helps later diagnosis.
