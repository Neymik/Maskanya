# Channel B PoC — WebRTC viability check

**What this tests:** the lowest possible bar — does WebRTC `RTCPeerConnection` + `DataChannel` work *at all* in a Russian browser, on a Russian network, against a public STUN server?

If WebRTC itself is broken from a given RU ISP, then Channel B (which depends on WebRTC over Yandex Telemost SFU) is dead before we even start writing pion code. So we test WebRTC first, in isolation, before investing in olcRTC.

**This is NOT a Telemost test.** It's a "is WebRTC even available" test. Telemost-specific testing comes after the spec's Phase 4 work begins.

## How to run

1. Copy `manual-test.html` to a Russian device (USB, email to yourself, host on Yandex.Disk public link, etc.).
2. Open it in two browser tabs (or two browsers, or two devices on the same RU network).
3. In **tab 1**, click "Create offer". Copy the offer SDP from the textbox.
4. In **tab 2**, paste it into "Remote SDP" and click "Set remote + create answer". Copy the answer SDP.
5. In **tab 1**, paste the answer into "Remote SDP" and click "Set remote".
6. Both tabs should display "DataChannel open". Type messages in the lower textbox in either tab; they appear in the other.

## What success means

- DataChannel reaches "open" state on both sides → WebRTC works for Channel B.
- Bytes flow both ways → DataChannel is functional. Channel B is buildable.

## What failure means

- ICE gathering stalls (no candidates after 30s) → STUN traffic blocked. Try with a Yandex/VK STUN server (planned for the real Channel B anyway).
- Offers/answers exchange but DataChannel never opens → DTLS/SCTP blocked. Channel B won't work in this regime.
- DataChannel opens but bytes never arrive → SCTP messages dropped mid-flight. Diagnostic only.

## Notes

- The HTML uses Google's public STUN (`stun:stun.l.google.com:19302`) for ICE. If you're testing under whitelist-mode, this STUN will fail because Google IPs aren't whitelisted. That's expected. For whitelist-mode testing, change the STUN URL in the HTML to one of:
  - `stun:stun.yandex.net:3478`  (sometimes available)
  - or run a STUN inside a YC VM
- The two tabs talk peer-to-peer. There's no SFU in the middle. Real Channel B uses Telemost's SFU; this PoC doesn't validate that path. But if peer-to-peer WebRTC fails locally, SFU won't save you.
- If both tabs are on the same machine, ICE will pick host candidates and never even hit STUN. To test STUN traversal, run the two tabs from two different networks (e.g. laptop + phone tethered to mobile data) and exchange SDPs via shared file/email.

## Files

- `manual-test.html` — single-file demo; no build step, no dependencies, runs in any modern browser.
