# Channel B carrier matrix — empirical findings

Status as of 2026-05-13, against upstream `openlibrecommunity/olcrtc @ c74d171`.

## Tested combinations

| Carrier | Transport | Result | Notes |
|---|---|---|---|
| **wbstream** | datachannel | ✅ **Works**, 4.7 Mbps sustained 5 min, 0 errors | Verified 2026-05-12. Currently impacted by wbstream API outage (502) — Wildberries side. |
| **wbstream** | gen-mode | ✅ Local UUID OK | Returns valid UUIDv7 for room IDs. |
| jazz | datachannel | ❌ Not viable | Upstream docs warn jazz IP-bans datachannel patterns. Also: jazz auto-gen produces RoomID without Password → preconnect 400. |
| jazz | vp8channel | ⚠️ **Link connects, data path doesn't** | Server logs `Link connected`; client logs `OpenStream failed: timeout` every ~30 s. Either upstream bug or jazz API regression in the data-transport open. |
| jazz | seichannel | ⚠️ Same as vp8channel | Probe shows `Jazz joining room: <name>` then no data; not investigated to completion. |
| jazz | gen-mode | ⚠️ Returns RoomID without Password | Real meeting IS created on SaluteJazz (`createRoom` call succeeds), but `Gen()` discards the Password from the response. Server/client can't authenticate with just the RoomID. **Workaround**: bootstrap by running `srv -id any` and capturing the logged `RoomID:Password` line. |
| telemost | (any) | ⚠️ Auto-gen unsupported | Upstream returns `unsupported carrier: telemost does not support room generation`. Requires operator to create a meeting at https://telemost.yandex.ru/ (Yandex account needed) and use the resulting room URL fragment as `-id`. |

## Recommended fallback strategy for operator-side outages

**Primary**: wbstream + datachannel (current production path; deployed as `maskanya-olcrtc-bridge.service` on ZOV).

**When wbstream is down**: today's options are limited.

1. **Wait it out.** Wildberries API outages have historically been hours, not days. The current outage started ~2026-05-12 23:00 JST and is ongoing at 12:30 next day.
2. **Use Channel A (VLESS+Reality) instead** if available — it doesn't share wbstream's failure domain.
3. **Manual SaluteJazz bootstrap** if you really need olcrtc:
   ```bash
   # On any machine with the binary:
   ./maskanya-olcrtc -mode srv -carrier jazz -transport vp8channel \
     -vp8-fps 25 -vp8-batch 1 \
     -id any -client-id default -key <hex64> \
     -link direct -dns 1.1.1.1:53 -data /tmp/data
   # First log line: `Jazz room created: <RoomID>:<Password>`
   # Kill it. Use the captured "RoomID:Password" as `-id` on both server and client.
   ```
   This gets you to the `Link connected` state. Data flow is blocked by the OpenStream issue noted above — **so this is not a usable end-user fallback today.** Useful for reproducing the bug for an upstream report.
4. **Manual Telemost path**: create a meeting at telemost.yandex.ru, use its short ID as `-id` for jazz-style operation. Untested by us — same `OpenStream`-class issue likely applies, since jazz and telemost share the same transport surface.

## What we deployed

- `experiments/b-webrtc/systemd/maskanya-olcrtc-jazz-bridge.service` — second systemd unit on ZOV (separate `StateDirectory=maskanya-olcrtc-jazz`, separate env file).
- `experiments/b-webrtc/scripts/deploy-jazz-zov.sh` — pushes the jazz unit + env to ZOV.
- `experiments/b-webrtc/scripts/run-client-jazz.sh` — operator launcher for the jazz client.
- `/etc/maskanya/olcrtc-jazz.env` on ZOV — same key as wbstream, jazz-formatted RoomID:Password.

The jazz unit is currently `loaded; disabled; inactive (dead)` — not started, because the OpenStream issue makes it not actually useful. Re-investigation is warranted when:
- Upstream `openlibrecommunity/olcrtc` ships a fix for the gen-Password issue or the OpenStream-with-jazz behavior.
- Or we find time to instrument the vp8channel/jazz code path and trace where the stream open fails.

## What we DID prove valuable

The exercise demonstrated:
- **The parallel-systemd-units pattern works** for carrier separation (and by extension for multi-device, per `USAGE.md`).
- **`mage cross` + the same binary supports all three carriers** — switching is a runtime flag.
- **The wbstream-only single-point-of-failure is real**, and Wildberries' API has been down ~13 hours of wall-clock during this session. Plan 04-05 is genuinely needed and harder than it looks.

## Recommendations for future work

1. **Open an upstream issue** on github.com/openlibrecommunity/olcrtc covering:
   - `-mode gen` for jazz drops the Password; only the RoomID is returned. The combined form is required for `-mode srv`/`cnc`.
   - jazz + vp8channel/seichannel: peer connection establishes, `Link connected` logs, but app-level `OpenStream` times out indefinitely. Reproducible from JST.
2. **Companion app (04-03)** should know about all three carriers but at v0 only wire up wbstream; show "Channel B alternative carriers experimental" if user toggles.
3. **Marzban subscription URI (04-04)** should encode the carrier choice in the URI so per-user keys can target a specific carrier without operator coordination.
4. **Operational alerting**: ZOV should monitor wbstream API health (`curl https://stream.wb.ru/...` 5xx checking) and surface an alert when sustained, since "is the carrier up" is now a recurring question.

---
*Captured 2026-05-13.*
