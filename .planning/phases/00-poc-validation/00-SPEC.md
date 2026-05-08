# Phase 0: PoC Validation — Specification

**Created:** 2026-05-08
**Ambiguity score:** 0.10 (gate: ≤ 0.20)
**Requirements:** 3 locked

## Goal

Determine empirically whether the May-2026-hardened Channel A protocol stack (VLESS+Reality+XHTTP-stream-one+Vision+chrome-uTLS+Yandex-CDN-SNI) on `:443` passes current RU DPI when run on `MaskanyaHopMsk` (FirstVDS Moscow), AND whether the two whitelist-resident escape channels (WebRTC, YC Functions) are reachable on the protocol level. Output: a recorded PASS/PARTIAL/FAIL verdict for each of three validation requirements, with diagnostic artifacts captured.

## Background

The `2026-05-08-three-channel-vpn-design.md` spec was written from research, not measurement. The May 2026 RU regulatory regime (behavioural DPI, whitelist-mode L3 filtering, May-1 cross-border charges) shifted enough between Feb and May that no recent end-to-end deployment exists for confirmation. Habr articles 1009542, 1027276, 1027990, and the operator's own observation (existing v1 design assumed `:8443` and non-Yandex SNIs — both wrong under current rules) all point to the need for live verification before architectural commitment.

`experiments/a-vless/` (commit `5450497`) contains the deployable scaffolding. `experiments/b-webrtc/manual-test.html` contains the WebRTC viability test. `experiments/c-yc-function/` contains the YC fetch-relay PoC. None has been run yet.

## Requirements

1. **VAL-01 — Channel A handshake survives current RU DPI**: When a v2rayN/NekoRay client on a Russian network uses the PoC URI emitted by `experiments/a-vless/scripts/gen-client-uri.sh`, the client establishes a working tunnel.
   - Current: untested. Spec assumes pass; no measurement.
   - Target: `curl --socks5 127.0.0.1:10808 -m 15 https://ifconfig.me` from the RU client returns `82.146.35.191` (MSK's WAN IP).
   - Acceptance: A successful curl as above AND a 5-minute mixed-browsing session (≥3 page loads + a 2-minute video stream) without disconnect, recorded in `experiments/a-vless/RESULTS.md`.

2. **VAL-02 — WebRTC DataChannel works in a Russian browser**: The browser-only loopback test in `experiments/b-webrtc/manual-test.html` reaches an "open" DataChannel state from a Russian device, and bytes flow both ways between the two tabs/devices.
   - Current: untested. Habr 1027276 marks olcRTC pre-alpha; no claim about whether basic WebRTC works in RU.
   - Target: A "DataChannel: open" state on both peers AND at least one round-trip text message recorded.
   - Acceptance: Operator screenshot or note of both peers showing "DataChannel: open" + bidirectional message log, captured in `experiments/b-webrtc/RESULTS.md` (created in this phase).

3. **VAL-03 — YC Function path works end-to-end**: A deployed YC Function is reachable from a RU client AND can fetch foreign URLs.
   - Current: untested. The fetch-relay function in `experiments/c-yc-function/index.js` exists but has not been deployed.
   - Target: From a RU client, `curl -X POST https://functions.yandexcloud.net/<id> -H 'Authorization: Bearer <token>' -d '{"url":"https://ifconfig.me"}'` returns 200 with body containing a YC-resident IP (NOT the RU client's IP).
   - Acceptance: Captured curl response in `experiments/c-yc-function/RESULTS.md` (created in this phase) showing successful fetch + non-RU egress IP.

## Boundaries (locked)

- **In scope**: empirical execution of `experiments/a-vless/`, `experiments/b-webrtc/`, `experiments/c-yc-function/` against current networks; recording results.
- **Out of scope**: any code changes beyond failure-mode-triage SNI/transport flips in `msk.json.tmpl`; deploying anything to `ZenithOfVastness`; integrating with Marzban; touching production `xray-maskanya`; building the companion app or olcRTC bridge.
- **Configuration mutation allowed**: editing `experiments/a-vless/configs/msk.json.tmpl` and `experiments/a-vless/scripts/gen-client-uri.sh` to cycle SNIs/flow modes during failure triage. All configs `.gitignore`d after rendering — only template + RESULTS.md committed.

## Acceptance Criteria (the gate to Phase 1)

Phase 0 is **complete** when **all three** of the following are true:

1. `experiments/a-vless/RESULTS.md` exists, committed, with a verdict line: `PASS` / `PARTIAL` / `FAIL`.
2. `experiments/b-webrtc/RESULTS.md` exists, committed, with a verdict line.
3. `experiments/c-yc-function/RESULTS.md` exists OR explicitly noted as "skipped — no YC account in v0.1 scope" in the Phase 0 summary.

Phase 0 is a **soft gate** — its verdicts inform Phase 1 plan content but don't block the phase from being formally complete. PASS on VAL-01 → Phase 1 starts as designed; FAIL on VAL-01 → Phase 1 reshapes to deprioritize Channel A and accelerate Channel C.

## Reference

- Underlying design: `docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md`
- Pre-built artifacts: `experiments/`
- Habr sources: 1009542, 1027276, 1027990, 1021160, 992240, 1017492 (cited in spec "Sources")
