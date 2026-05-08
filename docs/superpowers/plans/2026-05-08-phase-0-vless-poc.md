# Phase 0: VLESS PoC Implementation Plan

**Status:** SUPERSEDED on 2026-05-08 by `.planning/phases/00-poc-validation/00-01-PLAN.md` (rewritten under GSD methodology with PROJECT/REQUIREMENTS/ROADMAP/STATE backing). The new plan covers all three validation requirements (VAL-01, VAL-02, VAL-03), not just Channel A. Use the GSD plan as the authoritative execution document.

---

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate that VLESS + Reality + XHTTP-stream-one + Vision + chrome uTLS + Yandex CDN SNI on `:443` actually passes current RU DPI when listening on `MaskanyaHopMsk` (FirstVDS Moscow). Single empirical answer: yes → proceed to Phase 1; no → go to Channel C.

**Architecture:** Single-hop topology — client → MSK :443 → MSK direct egress. ZOV is untouched. The PoC tests the genuinely uncertain client-MSK leg in isolation; multihop wiring (MSK → ZOV via nginx SNI demuxer) becomes Phase 1 work with low residual risk *if* this PoC passes.

**Tech Stack:** `xray-core` v25.5.5 (XHTTP + stream-one + Vision support), bash deploy scripts (`experiments/a-vless/scripts/*.sh`), systemd unit on MSK, additive iptables, RU client (v2rayN ≥6.46 or NekoRay ≥3.27).

**Reference spec:** [`docs/superpowers/specs/2026-05-08-three-channel-vpn-design.md`](../specs/2026-05-08-three-channel-vpn-design.md) — see "Port discipline" and "Channel A".

**Pre-existing artifacts** (already committed in `5450497`):
- `experiments/a-vless/configs/msk.json.tmpl`
- `experiments/a-vless/scripts/keygen.sh`, `render.sh`, `deploy.sh`, `gen-client-uri.sh`, `teardown.sh`
- `experiments/a-vless/README.md`

This plan **executes** those artifacts and captures the empirical result. Almost no code changes. Anything that *does* require code changes only triggers in failure-mode triage (Task 6).

---

## File Structure

| File | Role | Status |
|---|---|---|
| `experiments/a-vless/configs/msk.json.tmpl` | xray inbound template (Reality+XHTTP+Vision on `:443`, Yandex SNI) | exists, read-only in PoC |
| `experiments/a-vless/scripts/*.sh` | keygen / render / deploy / URI-gen / teardown | exists, read-only in PoC |
| `experiments/a-vless/.env.poc-a` | generated env vars (private keys + UUID) | created in Task 2; `.gitignore`d |
| `experiments/a-vless/configs/msk-rendered.json` | rendered config produced by `render.sh` | created in Task 2; `.gitignore`d |
| `experiments/a-vless/RESULTS.md` | empirical findings; what passed / failed / pcap notes | created in Task 7 |
| `.gitignore` | ensure rendered configs and .env are never committed | created/updated in Task 1 |

Directory exists. Nothing structural to create.

---

## Task 0: Add `.gitignore` entries for generated artifacts

**Files:**
- Create or modify: `experiments/a-vless/.gitignore`

- [ ] **Step 1: Write the gitignore**

Create `experiments/a-vless/.gitignore`:

```
# Generated artifacts — never commit
.env.poc-a
configs/msk-rendered.json
*.pcap
RESULTS-private.md
```

- [ ] **Step 2: Verify it works**

```bash
cd /Users/neymik/Documents/maskanya
echo "test" > experiments/a-vless/.env.poc-a
git check-ignore experiments/a-vless/.env.poc-a
```

Expected: prints `experiments/a-vless/.env.poc-a` (means it's ignored).

```bash
rm experiments/a-vless/.env.poc-a
```

- [ ] **Step 3: Commit**

```bash
git add experiments/a-vless/.gitignore
git commit -m "Phase 0: gitignore PoC-generated artifacts"
```

---

## Task 1: Pre-flight verification

**Goal:** confirm the deploy preconditions are met before running deploy.sh. Better to abort here than mid-deploy.

**Files:** none modified — read-only checks.

- [ ] **Step 1: Confirm SSH alias `MaskanyaHopMsk` resolves and authenticates**

Run:

```bash
ssh -o ConnectTimeout=10 -o BatchMode=yes MaskanyaHopMsk 'echo ok && whoami && uname -a'
```

Expected: `ok`, then a username (probably `admin` or `root`), then `Linux ... 6.8.0-... Ubuntu ...`. If this errors out — fix `~/.ssh/config` first; everything downstream depends on it.

- [ ] **Step 2: Confirm SSH alias `ZenithOfVastness` works (needed by keygen.sh for the x25519 binary)**

Run:

```bash
ssh -o ConnectTimeout=10 -o BatchMode=yes ZenithOfVastness 'test -x /usr/local/bin/xray-maskanya && echo found'
```

Expected: `found`. If the binary is missing (e.g. ZOV bootstrap was rolled back), fall back to installing xray locally — see Step 3.

- [ ] **Step 3: Local toolchain check**

Run:

```bash
for cmd in curl unzip openssl uuidgen envsubst scp ssh; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "ok: $cmd"
    else
        echo "MISSING: $cmd"
    fi
done
```

Expected: every line `ok:`. If any are missing on macOS:
```bash
brew install gettext     # provides envsubst
brew install ossp-uuid   # provides uuidgen (already on macOS)
```

- [ ] **Step 4: Confirm MSK :443 is free**

Run:

```bash
ssh MaskanyaHopMsk 'ss -tlnp 2>/dev/null | (grep ":443 " || echo "443 is FREE")'
```

Expected: `443 is FREE`. If something is bound (rare post-wipe — but `ssh.socket` on Ubuntu 22.10+, leftover nginx, or our own xray-poc from a prior PoC run could be there), inspect it:

```bash
ssh MaskanyaHopMsk 'ss -tlnp | grep ":443 "'
ssh MaskanyaHopMsk 'systemctl status xray-poc 2>/dev/null'
```

If it's a previous `xray-poc` run, run teardown first:

```bash
cd experiments/a-vless && ./scripts/teardown.sh
```

If it's something else (nginx, ssh.socket on `:443` weirdness, etc.) — stop and decide: kill the listener manually, or pick a different host. **Do not** auto-kill production-shaped services without operator confirmation.

- [ ] **Step 5: Confirm `experiments/a-vless/` scripts are executable**

Run:

```bash
ls -l experiments/a-vless/scripts/*.sh
```

Expected: every file mode starts with `-rwxr-xr-x` (or similar — `x` bit set). If not:

```bash
chmod +x experiments/a-vless/scripts/*.sh
```

(No commit — pre-flight is read-only.)

---

## Task 2: Generate Reality keys + render config

**Files:**
- Create: `experiments/a-vless/.env.poc-a`
- Create: `experiments/a-vless/configs/msk-rendered.json`

- [ ] **Step 1: Generate keys to a session env file**

Run from repo root:

```bash
cd experiments/a-vless
./scripts/keygen.sh > .env.poc-a
```

Inspect the file:

```bash
cat .env.poc-a
```

Expected: 4 lines like
```
export MSK_REALITY_PRIVATE_KEY='ALK...'
export MSK_REALITY_PUBLIC_KEY='Wxq...'
export MSK_SHORT_ID='a3f9b2c8'
export USER_UUID='11111111-2222-3333-4444-555555555555'
```

The private key is sensitive — `.env.poc-a` is `.gitignore`d (Task 0).

- [ ] **Step 2: Source the env vars into the current shell**

```bash
source .env.poc-a
echo "uuid=$USER_UUID short=$MSK_SHORT_ID pub=${MSK_REALITY_PUBLIC_KEY:0:8}..."
```

Expected: prints uuid, 8-hex short ID, and the first 8 chars of the public key.

- [ ] **Step 3: Render the xray config**

```bash
./scripts/render.sh
```

Expected output: `Rendered: configs/msk-rendered.json`.

- [ ] **Step 4: Verify the rendered config parses as JSON and contains the right fields**

```bash
jq '.inbounds[0] | {port, protocol, network: .streamSettings.network, mode: .streamSettings.xhttpSettings.mode, sni: .streamSettings.realitySettings.serverNames[0], fp: .streamSettings.realitySettings.fingerprint, dest: .streamSettings.realitySettings.dest}' configs/msk-rendered.json
```

Expected:
```json
{
  "port": 443,
  "protocol": "vless",
  "network": "xhttp",
  "mode": "stream-one",
  "sni": "storage.yandex.net",
  "fp": "chrome",
  "dest": "storage.yandex.net:443"
}
```

If any field is wrong, re-check the template and re-render. Don't proceed to deploy until this is exact.

(No commit — `.env.poc-a` and `msk-rendered.json` are gitignored.)

---

## Task 3: Deploy xray-poc to MSK

**Files:** none locally modified. Side-effects on MSK:
- `/opt/xray-poc/xray` (binary)
- `/opt/xray-poc/config.json`
- `/etc/systemd/system/xray-poc.service`
- one `iptables -I INPUT -p tcp --dport 443 -j ACCEPT` rule

- [ ] **Step 1: Run the deploy script**

From `experiments/a-vless/` (env still sourced from Task 2):

```bash
./scripts/deploy.sh
```

Expected output (last few lines):
```
✓ deployed. Run scripts/gen-client-uri.sh to get the v2rayN URI.
  Logs: ssh MaskanyaHopMsk journalctl -u xray-poc -f
```

The script also prints `systemctl status xray-poc.service` — confirm:
- `Active: active (running)`
- no errors in the last 5 log lines

If it says `Active: failed` or there's a stack trace, capture journalctl:

```bash
ssh MaskanyaHopMsk 'journalctl -u xray-poc --no-pager -n 50'
```

Common failures:
- *"address already in use"* → Task 1 Step 4 missed a listener; teardown and retry.
- *"key parse failed"* → re-run Task 2 (the env may have been mangled).
- *"failed to bind 0.0.0.0:443: permission denied"* → `CAP_NET_BIND_SERVICE` didn't take effect; check the systemd unit file is the one shipped in `deploy.sh`.

- [ ] **Step 2: Verify xray is listening on :443**

```bash
ssh MaskanyaHopMsk 'ss -tlnp | grep ":443 "'
```

Expected: one line, process is `xray` (pid in parentheses), local address `0.0.0.0:443`.

- [ ] **Step 3: Verify firewall accepts inbound :443**

```bash
ssh MaskanyaHopMsk 'iptables -L INPUT -nv --line-numbers | grep -E "tcp dpt:443"'
```

Expected: at least one ACCEPT rule for `tcp dpt:443`.

- [ ] **Step 4: External reachability sanity check**

From your laptop (foreign IP, NOT routed through any VPN):

```bash
curl -kIm5 https://82.146.35.191:443/ 2>&1 | head -3
```

Expected output: TLS will succeed (Reality returns the spoofed Yandex cert) and curl will print headers — but content will be wrong (it's xray's fallback, not real Yandex). What we care about: TLS handshake completes, doesn't TCP-RST or timeout. Anything starting with `HTTP/`, `Server:`, `Content-Type:`, etc. = port 443 reachable from outside.

If curl times out: ISP-level filtering of FirstVDS, or another network hop is dropping. Diagnose with `mtr 82.146.35.191` before continuing.

(No commit yet — checkpoint after the actual RU test.)

---

## Task 4: Generate client URI and stage it for testing

**Files:** none modified. Outputs the URI to copy.

- [ ] **Step 1: Generate the URI**

```bash
./scripts/gen-client-uri.sh
```

Expected: a single-line `vless://...` URI ending in `#Maskanya-PoC-A`. Contains `type=xhttp&mode=stream-one&path=%2Fpoc&security=reality&pbk=...&sid=...&sni=storage.yandex.net&fp=chrome&flow=xtls-rprx-vision`.

- [ ] **Step 2: Save the URI to a private notes file**

```bash
./scripts/gen-client-uri.sh > .uri-poc-a.txt
cat .uri-poc-a.txt
```

(`.uri-poc-a.txt` not in `.gitignore` because `.env.poc-a` already is — but the URI also embeds the public key + UUID. Add to `.gitignore` if you want belt-and-suspenders. URI alone isn't a credential without the server, so risk is low.)

---

## Task 5: Operator-side smoke test (foreign network)

**Goal:** confirm the URI works on the operator's laptop (which is not in RU). This isolates "does the protocol stack itself function" from "does RU DPI block it". If this fails, we have a config bug, not a regulatory problem.

**Files:** none modified.

- [ ] **Step 1: Configure v2rayN / NekoRay on the operator's laptop**

In v2rayN: Server → Add → Paste URI from `.uri-poc-a.txt`.
In NekoRay: Program → Add profile from clipboard.

Don't enable system proxy yet.

- [ ] **Step 2: Test through the SOCKS5 listener of the client**

v2rayN/NekoRay exposes a local SOCKS5 (typically `127.0.0.1:10808` or `127.0.0.1:1080` — check the client's status bar).

Set `SOCKS_PROXY` accordingly, then:

```bash
SOCKS_PROXY=127.0.0.1:10808
curl --socks5 $SOCKS_PROXY -m 15 https://ifconfig.me
```

Expected: prints `82.146.35.191`. That's MSK's WAN IP — confirms the tunnel terminates at MSK and egresses via freedom.

If you get something else:
- *Your home IP* → tunnel didn't establish; check v2rayN's connection log.
- *A different IP* → maybe a different proxy is interfering; disable system proxy.
- *Timeout* → v2rayN couldn't connect to MSK; check journalctl on MSK for handshake failures.

- [ ] **Step 3: Capture xray's view of the connection**

While the curl above runs (or ran), from the laptop:

```bash
ssh MaskanyaHopMsk 'journalctl -u xray-poc --no-pager -n 30 --since "1 minute ago"'
```

Expected: at least one line mentioning the connection. xray with `loglevel: warning` is mostly quiet on success — a clean log = good. Errors like "rejected", "invalid", "TLS handshake error" are red flags.

(No commit. Continue to RU test.)

---

## Task 6: RU-side test — the actual answer

**Goal:** the empirical question this whole PoC exists for. Run this on a Russian network.

**Files:** `experiments/a-vless/RESULTS.md` (created in Task 7).

- [ ] **Step 1: Set up a v2rayN / NekoRay client on a RU device**

Options:
- Operator's own RU SIM via mobile hotspot to laptop
- Operator's RU residential ISP if available
- A trusted contact in RU (ship them the URI via Telegram/Signal — URI alone is fine; without server access nobody can use it maliciously beyond burning your free quota)

Paste the same URI from `.uri-poc-a.txt`.

- [ ] **Step 2: Quick handshake test**

From the RU device, with the v2rayN tunnel enabled:

```bash
curl --socks5 127.0.0.1:10808 -m 15 https://ifconfig.me
```

Expected if success: `82.146.35.191`.

Record the *exact* result and timing. If it succeeds first try, that's the answer — Channel A is alive in current DPI conditions.

- [ ] **Step 3: Sustained-load test (catches the 30-second-then-dies pattern)**

Open a browser through v2rayN's system proxy and do a "real" browsing session for 5 minutes:
- Load 3-5 pages of normal content (news, GitHub, anything bigger than a few KB)
- Watch for the moment it stops loading. Note the wallclock time.
- Optionally: stream a YouTube video for ≥2 min.

The 16 KB-payload classifier (Habr 1000694) shows up here, not in the curl smoke test.

- [ ] **Step 4: Capture a pcap from the RU side (optional but valuable)**

If anything looks off, get a pcap for forensics:

```bash
# On the RU device:
sudo tcpdump -i any -w channel-a-test-$(date +%Y%m%d-%H%M).pcap host 82.146.35.191 and tcp port 443
```

Run for ~60 seconds while reproducing the issue. Stop with Ctrl-C. File goes into `experiments/a-vless/` (gitignored — pcaps can contain sensitive data).

- [ ] **Step 5: Decision branch**

Based on what happened in Steps 2-3, choose the next task:

| Result | Next |
|---|---|
| Handshake succeeds AND sustains 5+ min of browsing AND streaming works | → Task 7 (record success, plan Phase 1) |
| Handshake fails with TCP RST | → Task 6.A (alternative SNI) |
| Handshake succeeds but no data flows | → Task 6.B (drop Vision) |
| Works for ~30s then dies | → Task 6.B (drop Vision) — Vision's payload geometry is a likely trigger |
| Inconsistent across networks (works on one carrier, not another) | → Task 7 (record partial; Phase 1 still proceeds) |

---

## Task 6.A: Failure triage — alternative SNI

**Skip this task if Task 6 succeeded.**

**Goal:** if the handshake fails, the SNI may be in a regional blacklist. Cycle through alternatives.

**Files:**
- Modify: `experiments/a-vless/configs/msk.json.tmpl` (line 25 — `dest`; line 27 — `serverNames[0]`)

- [ ] **Step 1: Switch SNI to `yastatic.net`**

Edit `experiments/a-vless/configs/msk.json.tmpl`:

```jsonc
"dest": "yastatic.net:443",
"xver": 0,
"serverNames": ["yastatic.net"],
```

(Two values: `dest` and `serverNames[0]` — both must change to the same domain.)

- [ ] **Step 2: Re-render and redeploy**

```bash
./scripts/render.sh
./scripts/deploy.sh
```

Both are idempotent — the second deploy just overwrites config and restarts the service.

- [ ] **Step 3: Regenerate URI and retest**

```bash
./scripts/gen-client-uri.sh > .uri-poc-a.txt
```

The URI's `&sni=` parameter must match the new SNI for the client. Re-paste into v2rayN on the RU device. Re-run Task 6 Step 2.

- [ ] **Step 4: If `yastatic.net` also fails, try the next candidate**

Cycle through, in this order (each iteration = re-edit template, re-render, re-deploy, re-paste URI, retest):
1. `avatars.mds.yandex.net`
2. `vkuser.net`
3. `userapi.com`
4. `cdn-frankfurt-1.dropbox.com` (foreign-CDN canary; if this works but Yandex SNIs don't, the SNI blacklist hypothesis is wrong and behavioural classifier is the real cause)

If all four fail with handshake errors, Channel A is currently non-viable. → Task 7 (document failure) → start work on Channel C.

---

## Task 6.B: Failure triage — drop Vision

**Skip this task if Task 6 succeeded.**

**Goal:** if data doesn't flow or works briefly then dies, the Vision flow is producing detectable post-handshake geometry. Switch to plain XHTTP `auto` mode without Vision.

**Files:**
- Modify: `experiments/a-vless/configs/msk.json.tmpl`

- [ ] **Step 1: Drop Vision flow and switch XHTTP mode**

Edit `experiments/a-vless/configs/msk.json.tmpl`:

```jsonc
// Line 11-12: client flow
"clients": [
  { "id": "${USER_UUID}", "flow": "", "email": "poc-user@maskanya" }
],
```

```jsonc
// Line 18-21: streamSettings.xhttpSettings.mode
"xhttpSettings": {
  "path": "/poc",
  "mode": "auto",
  "xPaddingBytes": "100-1000"
},
```

(Two changes: `flow` becomes empty string; `mode` becomes `"auto"`.)

- [ ] **Step 2: Re-render and redeploy**

```bash
./scripts/render.sh
./scripts/deploy.sh
```

- [ ] **Step 3: Regenerate URI for client**

```bash
./scripts/gen-client-uri.sh
```

The URI must NOT include `&flow=xtls-rprx-vision` and must use `&mode=auto`. Edit `gen-client-uri.sh` if it still emits the Vision flow:

```bash
# Inside scripts/gen-client-uri.sh, around line 17:
# OLD: ...&flow=xtls-rprx-vision#Maskanya-PoC-A
# NEW: ...#Maskanya-PoC-A          (drop the flow param entirely)
# OLD: ...&mode=stream-one&path=...
# NEW: ...&mode=auto&path=...
```

Re-run, re-paste URI, retest with Task 6 Step 2 + 3.

- [ ] **Step 4: If still fails, try TCP transport (no XHTTP)**

This is the simplest possible Reality config — same as v1 but with chrome fingerprint. Used as a "is it XHTTP that's the problem, or Reality itself" canary.

Edit `msk.json.tmpl`:

```jsonc
"streamSettings": {
  "network": "tcp",
  "security": "reality",
  ...
}
```

(Remove the `xhttpSettings` block entirely.)

Re-render, redeploy, retest. URI also drops the XHTTP params:

```
vless://UUID@82.146.35.191:443?type=tcp&security=reality&pbk=...&sid=...&sni=storage.yandex.net&fp=chrome#Maskanya-PoC-A-tcp
```

If even plain TCP+Reality+chrome+Yandex SNI fails: Reality itself is being caught in current DPI. Channel A non-viable; → Channel C.

---

## Task 7: Document the result

**Files:**
- Create: `experiments/a-vless/RESULTS.md`

- [ ] **Step 1: Write the findings**

Create `experiments/a-vless/RESULTS.md`:

```markdown
# Channel A PoC — Results

**Tested:** 2026-05-XX
**Tester:** <your handle>
**RU network:** <e.g. "MTS mobile hotspot, Moscow" or "Beeline residential, SPb">
**Final config that was tested:** SNI=<domain>, transport=<xhttp-stream-one | xhttp-auto | tcp>, flow=<vision | empty>

## Quick verdict

[ ] PASS — handshake + 5min browsing + streaming all worked
[ ] PARTIAL — handshake worked, sustained traffic failed; details below
[ ] FAIL — handshake or initial data flow broke

## Curl smoke test

Command: `curl --socks5 127.0.0.1:10808 -m 15 https://ifconfig.me`
Result: <verbatim output, e.g. `82.146.35.191`>

## Sustained traffic

- 5min mixed browsing: <observation>
- YouTube video (2min+): <observation>
- Time-to-failure (if any): <e.g. "died at 38s consistently">

## Failure-mode triage attempts

- [ ] Switched SNI to <list>: <result>
- [ ] Dropped Vision: <result>
- [ ] Plain TCP fallback: <result>

## Pcap

If captured: filename, size, brief description of what's visible.

## Recommendation

- If PASS: proceed to Phase 1 (`writing-plans` for nginx_sni_demux + xray_entry/xray_exit rewrites).
- If FAIL: skip Phase 1 for VLESS; focus on Channel C.
- If PARTIAL: document the working config combination — Phase 1 uses it as the baseline. The specific carrier behaviour goes into the project memory.
```

- [ ] **Step 2: Commit results**

```bash
cd /Users/neymik/Documents/maskanya
git add experiments/a-vless/RESULTS.md
git commit -m "Phase 0 PoC results: <PASS|PARTIAL|FAIL>"
```

(If you also modified `msk.json.tmpl` or `gen-client-uri.sh` in Task 6.A/6.B and want to capture which config-combination ended up working, commit those edits too. If you cycled through many SNIs and the final state isn't representative, revert the template back to the storage.yandex.net+stream-one+vision baseline before committing — RESULTS.md captures the variants that were tried.)

---

## Task 8: Teardown (only if PoC failed and you're moving on)

**Skip if PoC passed and Phase 1 starts immediately** — leave xray-poc running while Phase 1 work is in progress; tear down only when Phase 1 deploys the production xray inbound on MSK.

**Files:** none locally modified. Removes side-effects on MSK.

- [ ] **Step 1: Run teardown**

```bash
cd experiments/a-vless
./scripts/teardown.sh
```

Expected output:
```
→ MaskanyaHopMsk: stopping + removing xray-poc
→ MaskanyaHopMsk: removing iptables rule for :443
✓ torn down.
```

- [ ] **Step 2: Verify clean state on MSK**

```bash
ssh MaskanyaHopMsk 'systemctl status xray-poc 2>&1 | head -3 ; \
                   test -d /opt/xray-poc && echo "DIR STILL EXISTS" || echo "dir gone" ; \
                   iptables -L INPUT -n | grep -q "dpt:443" && echo "iptables rule remains" || echo "iptables clean"'
```

Expected:
- `Unit xray-poc.service could not be found.` (or "inactive (dead)")
- `dir gone`
- `iptables clean`

If anything is "still exists" / "remains", inspect manually and remove.

- [ ] **Step 3: Wipe local generated artifacts**

```bash
rm -f .env.poc-a .uri-poc-a.txt configs/msk-rendered.json *.pcap
```

(All gitignored, so they're not in version control — but they contain the private key.)

---

## Self-review checklist (already run; results inline)

**Spec coverage:** Phase 0 in the spec roadmap calls for "validate the protocol stack before architectural commitments" — Tasks 1-8 do exactly that and produce a PASS/FAIL/PARTIAL result.

**Placeholder scan:** none — every step has exact commands and expected output.

**Type consistency:** `MSK_REALITY_PRIVATE_KEY`, `MSK_REALITY_PUBLIC_KEY`, `MSK_SHORT_ID`, `USER_UUID` are the four env vars; same names in keygen.sh, render.sh, msk.json.tmpl. Confirmed.

**Failure-mode triage discipline:** Tasks 6.A and 6.B are explicitly skip-if-passed; both terminate at "Channel A non-viable → Channel C" instead of looping forever.
