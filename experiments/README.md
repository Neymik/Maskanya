# Maskanya — Three-Channel PoC

Minimal proof-of-concept for the three channels in the [2026-05-08 design spec](../docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md). Goal: answer "does this approach actually work in the May 2026 RU regime" before investing in Ansible roles, Marzban integration, or a companion app.

**Scope per channel:** the smallest thing that produces a yes/no answer.

| Channel | What this tests | Effort |
|---|---|---|
| A — single-hop VLESS+Reality+XHTTP | Does xray-core 25.x with stream-one + chrome fp + Yandex CDN SNI on `:443` survive RU DPI when run on FirstVDS? | ~1h, MSK only |
| C — YC Function | Can a function on `functions.yandexcloud.net` be reached from RU AND reach foreign IPs? | ~1h, requires YC account |
| B — WebRTC | Does WebRTC DataChannel work in a Russian browser at all? Loopback test only. | ~5min, browser only |

**Port discipline (cross-cutting).** Under the May 2026 RU regime, any TCP port that isn't `:22 / :80 / :443` is treated as suspicious — including widely-used HTTPS alternatives like `:8443`, `:2053`, `:2096`. Earlier drafts of these experiments used non-standard ports for "isolation"; the current versions stick to `:443` everywhere. ZOV-side multiplexing of multiple `:443` services (xray Reality + 13 production vhosts + YC bridge) requires the `nginx_stream` SNI demuxer described in the design spec — that's Phase 1 work, not PoC scope. Therefore Channel A's PoC is **single-hop on MSK only**: client → MSK :443 → MSK direct egress. ZOV is untouched.

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

- **Channel A (single-hop):** `curl https://ifconfig.me` through the tunnel returns MSK's IP (`82.146.35.191`), not the client's home IP. We're not testing exit geography in this PoC — we're testing whether RU DPI lets our handshake + payload through. If yes, the protocol stack is viable; ZOV-side multihop work moves to Phase 1.
- **Channel C:** the function reachable from RU AND able to fetch foreign URLs (e.g. `ifconfig.me` returns a YC-resident IP, indicating egress from YC's network).
- **Channel B:** DataChannel reaches `open` state and bytes flow between two browser tabs.

Failure modes to log when reporting:
- TCP RST during handshake → DPI is killing it at L7
- TCP timeout → likely L3 drop or ISP-level block
- Handshake completes but no data flows → behavioral classifier or RST-on-payload
- Works for 30s then dies → 16KB-threshold-style trigger
- Works inconsistently across networks → ISP-specific TSPU configuration

Capture `tcpdump -i any -w channel-X.pcap host <server-ip>` from the RU side for ~60s of testing. Helps later diagnosis.
