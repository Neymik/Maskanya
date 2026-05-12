# Channel B — using olcRTC for browsing

Two perspectives in one doc:
- **Part 1**: you, on your Mac, day-to-day testing or actual use.
- **Part 2**: shipping Channel B to a Russian user.

The pipe is always:
```
your device → SOCKS5 :1080 → olcrtc client → wbstream SFU (Moscow) → olcrtc server → ZOV (NL) → open internet
```

Egress IP you'll see at `ifconfig.me` when it's working: **`103.137.249.134`** (ZOV).

---

## Part 1 — using it from your Mac

### One-time setup (already done)

Binary at `experiments/b-webrtc/build/maskanya-olcrtc-darwin-arm64`. Secrets at `experiments/b-webrtc/.env.olcrtc-v0` (gitignored, mode 600). Server unit deployed on ZOV (loaded, disabled, currently inactive).

### Start a session

In one terminal:
```bash
ssh ZenithOfVastness 'sudo systemctl start maskanya-olcrtc-bridge'
./experiments/b-webrtc/scripts/run-client.sh    # leave running
```

After ~5–15 seconds you'll see `SOCKS5 server listening on 127.0.0.1:1080` and (with `-debug`) some pion ICE chatter ending in `peer connection state changed: connected`.

Quick sanity check from a second terminal:
```bash
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
# → 103.137.249.134
```

### Pick a way to send your browser through it

#### Option A — Firefox only (recommended for daily use)

Cleanest because it scopes the tunnel to one app and doesn't touch the OS. Settings → search "proxy" → **Network Settings → Settings**:

- **Manual proxy configuration**
- **SOCKS Host:** `127.0.0.1`  **Port:** `1080`
- **SOCKS v5**
- ✅ **Proxy DNS when using SOCKS v5** ← important, prevents DNS leak
- ✅ **Use this proxy server for FTP and HTTPS** (it'll grey out — that's fine)

Restart any open tabs. Visit `https://ifconfig.me` — should show ZOV's IP. Visit `https://browserleaks.com/ip` for a fuller check.

To turn off: same screen → **No proxy**.

#### Option B — macOS system-wide SOCKS proxy

Covers Safari, Chrome, and most apps that respect system proxy settings (some explicitly bypass: Slack, some Electron apps, anything using its own HTTP stack).

**System Settings → Network → [your active interface, Wi-Fi usually] → Details → Proxies**:

- ✅ **SOCKS Proxy**
- Server: `127.0.0.1`  Port: `1080`
- Apply

To turn off: untick SOCKS Proxy.

#### Option C — Real system-wide TUN (everything, including apps that bypass system proxy)

Needed if Option B's app gives you the wrong IP, i.e., it bypasses the system proxy. Uses [Brook](https://github.com/txthinking/brook) (one-time install) to create a fake network interface that funnels all traffic into your SOCKS5.

```bash
brew install brook
# In a separate terminal — needs root:
sudo brook tun --tun-name utun99 --socks5 127.0.0.1:1080
```

`utun99` shows up as a network interface; all your Mac's TCP+UDP gets routed through olcrtc. Ctrl-C tears it down. The Mac's regular DNS and routing will reconfigure automatically.

Caveat: if olcrtc disconnects, your Mac's internet looks dead until Brook tears down. Easier to stop Brook first, then olcrtc, in that order.

#### Option D — A single command (test or scripting)

```bash
curl --socks5-hostname 127.0.0.1:1080 https://example.com
git -c http.proxy=socks5h://127.0.0.1:1080 clone https://github.com/foo/bar
```

For arbitrary commands without per-tool config, install `proxychains-ng`:
```bash
brew install proxychains-ng
# ~/.proxychains/proxychains.conf — set last line to:  socks5 127.0.0.1 1080
proxychains4 -q <any-command-here>
```

### End the session cleanly

```bash
# 1. Stop any tun2socks first (Option C only) — Ctrl-C the brook process
# 2. Stop the client (Ctrl-C in its terminal)
# 3. Stop the ZOV server:
ssh ZenithOfVastness 'sudo systemctl stop maskanya-olcrtc-bridge'
# 4. Revert browser/system proxy settings
```

---

## Part 2 — distributing Channel B to a Russian user

**Threat-model preamble:** v0 uses a single shared 32-byte ChaCha20 key + a single Room ID. Anyone who has the `.env.olcrtc-v0` file can decrypt all traffic between any client and ZOV using that key. Per-user keys derived from JWT come in plan 04-04 (Marzban subscription wiring). For v0, **only ship Channel B to people you'd trust with your own VPN credentials.**

### What to ship

1. **A binary for their OS.** All 9 platforms got built by `mage cross` and live at `experiments/b-webrtc/upstream/build/`:
   - Windows: `olcrtc-windows-amd64.exe`
   - Linux (most distros): `olcrtc-linux-amd64`
   - Linux ARM (Raspberry Pi etc.): `olcrtc-linux-arm64`
   - macOS Apple Silicon: `olcrtc-darwin-arm64`
   - macOS Intel: `olcrtc-darwin-amd64`
   - FreeBSD / OpenBSD: available
2. **Their `.env`** — the contents of your `experiments/b-webrtc/.env.olcrtc-v0`. They paste it into a local file on their machine.

### How to ship it (out-of-band, encrypted)

Pick **any one** of:
- **Signal** (recommended): attach binary, send `.env` contents as a separate message.
- **Telegram Secret Chat** (NOT regular chat).
- **Magic Wormhole** (`brew install magic-wormhole`) — `wormhole send file.exe` produces a passphrase you read aloud over a different channel. Server-side files never persist.
- **Encrypted ZIP** sent via any channel (`zip -e olcrtc.zip olcrtc-windows-amd64.exe .env.olcrtc-v0`); password over a different channel.

**Never send via:** plain email, unencrypted cloud link (Google Drive without password), SMS, Discord DM, regular Telegram chat.

### Recipient instructions — Windows (most common)

Send them this snippet. They paste into a PowerShell window:

```powershell
# 1. Put olcrtc.exe + olcrtc.env in the same folder, then cd there:
cd $env:USERPROFILE\Downloads\maskanya

# 2. Load the .env into the process environment:
Get-Content .\olcrtc.env | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.+)$') {
    [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
  }
}

# 3. Run the client. Leave this window open while using the tunnel.
.\olcrtc.exe `
  -mode cnc `
  -carrier $env:OLCRTC_CARRIER `
  -transport $env:OLCRTC_TRANSPORT `
  -id $env:OLCRTC_ROOM_ID `
  -client-id $env:OLCRTC_CLIENT_ID `
  -key $env:OLCRTC_KEY `
  -link direct `
  -dns 1.1.1.1:53 `
  -data .\data `
  -socks-host 127.0.0.1 `
  -socks-port 1080
```

Then in Firefox (cleanest) or system proxy (Settings → Network & internet → Proxy → Manual proxy setup → SOCKS): `127.0.0.1:1080`, SOCKS v5, "Proxy DNS through SOCKS5".

To verify, visit https://ifconfig.me → should show `103.137.249.134`.

To stop: Ctrl-C the PowerShell window, then revert proxy settings.

### Recipient instructions — Linux/macOS

```bash
mkdir -p ~/maskanya && cd ~/maskanya
# (place olcrtc-linux-amd64 and olcrtc.env in this folder)
chmod +x olcrtc-linux-amd64
source olcrtc.env
./olcrtc-linux-amd64 \
  -mode cnc \
  -carrier "$OLCRTC_CARRIER" \
  -transport "$OLCRTC_TRANSPORT" \
  -id "$OLCRTC_ROOM_ID" \
  -client-id "$OLCRTC_CLIENT_ID" \
  -key "$OLCRTC_KEY" \
  -link direct \
  -dns 1.1.1.1:53 \
  -data ./data \
  -socks-host 127.0.0.1 \
  -socks-port 1080
```

Then point apps at `127.0.0.1:1080` (SOCKS5).

### Combining Channel B with v2rayN / Hiddify (Windows recipients with existing VPN clients)

Many Russian users already run v2rayN or Hiddify-Next for Channel A (VLESS/Reality). They can use Channel B as an *upstream* of those:

- **v2rayN**: Add new server → Type: `SOCKS` → Address: `127.0.0.1` → Port: `1080`. Activate it. Now all v2rayN routing rules apply, but instead of dialing Channel A's VLESS, traffic exits via Channel B.
- **Hiddify-Next**: similar — add a SOCKS5 outbound, switch the active proxy to it.

This is how the future companion app (plan 04-03) will look — single UI, switchable between Channel A and Channel B.

### Recipient instructions — Android (via Termux)

Android doesn't run native binaries directly, but [Termux](https://termux.dev) provides a real arm64 Linux userspace inside its app sandbox. Static Go binaries like olcrtc Just Run in there.

The trick is then combining it with a SOCKS5-aware VPN consumer app (V2RayNG, Hiddify-Next, SagerNet) that uses Android's `VpnService` API to turn the local SOCKS5 listener into a system-wide TUN — so all the phone's apps route through olcrtc transparently.

Send the recipient:
- `olcrtc-linux-arm64` (~26 MB) — most modern Android phones are arm64
- The `.env.olcrtc-v0` contents

Their setup:
```bash
# 1. Install Termux from F-Droid (NOT Play Store — that one is abandoned)
#    Also install F-Droid version of "Termux:API" if you want notifications.
# 2. First Termux launch:
pkg update && pkg upgrade -y
termux-setup-storage              # grant the popup; gives access to /sdcard

# 3. Transfer files. Easiest:
#    - On your computer: pip install magic-wormhole && wormhole send olcrtc-linux-arm64
#    - On phone in Termux: pkg install python && pip install magic-wormhole && wormhole receive <code>
#    Repeat for olcrtc.env.
# OR copy the files to the phone via USB/AirDroid first, then in Termux:
#    cp /sdcard/Download/olcrtc-linux-arm64 ~/olcrtc
#    cp /sdcard/Download/olcrtc.env ~/

# 4. Make it runnable + start client:
mkdir -p ~/maskanya && cd ~/maskanya
mv ~/olcrtc-linux-arm64 ./olcrtc && chmod +x olcrtc
mv ~/olcrtc.env ./
source olcrtc.env
./olcrtc \
  -mode cnc \
  -carrier "$OLCRTC_CARRIER" \
  -transport "$OLCRTC_TRANSPORT" \
  -id "$OLCRTC_ROOM_ID" \
  -client-id "$OLCRTC_CLIENT_ID" \
  -key "$OLCRTC_KEY" \
  -link direct \
  -dns 1.1.1.1:53 \
  -data ./data \
  -socks-host 127.0.0.1 \
  -socks-port 1080
# Leave this Termux session running (use Termux session tabs).
```

Then in a SOCKS5-aware VPN consumer (install from F-Droid):
- **V2RayNG**: ☰ → Servers → ➕ → "Manual input [VLESS]" — wait, choose "SOCKS" — Address `127.0.0.1` Port `1080`. Tap → "v" to activate. Android shows a VPN profile prompt — accept. Now all phone traffic routes through olcrtc.
- **Hiddify-Next**: Add profile → Type SOCKS5 → `socks5://127.0.0.1:1080` → activate.
- **SagerNet / NekoBox**: similar SOCKS outbound config.

Verify in any browser: visit `https://ifconfig.me` → should show ZOV's NL IP.

**Two caveats with Android:**
- Termux + the VPN app must both stay running. Android's battery optimizer aggressively kills background apps; disable optimization for both in Settings → Apps.
- When the phone screen locks for long enough, the cellular radio can drop the WebRTC link's UDP keepalives. The olcrtc client doesn't always recover gracefully. Expect occasional reconnects.

**Alternative — `olcbox`:** the community has a packaged Android wrapper at [alananisimov/olcbox](https://github.com/alananisimov/olcbox). It's a single-APK install, no Termux required. **But:** we don't control it, can't audit the build supply chain, project activity is uneven. Riskier than the Termux DIY route. Mention to recipients but lean toward Termux for anyone security-sensitive.

### iOS — NOT supported in v0

The honest answer: iOS users cannot use Channel B in v0. iOS has no Termux equivalent — no way to run arbitrary binaries without jailbreaking — and:

- **App Store**: an explicit "bypass Russian censorship via parasitizing whitelisted Russian services" app would not pass review. Not happening.
- **Sideloading via AltStore / Sideloadly**: works technically; requires a paid Apple Developer account ($99/yr) refreshing certificates every year, or the free tier refreshing every 7 days. Operationally fragile, especially for non-technical users.
- **LAN-tethered (olcrtc on a home device + iPhone SOCKS5 to local IP)**: works at home only, useless when traveling or on cellular. Not a real mobile VPN.

**What iOS users should actually do:** use **Channel A (VLESS+Reality)** via existing app-store iOS clients like [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) (paid, ~$3), [FoXray](https://apps.apple.com/app/foxray/id6448898396) (free), [Streisand](https://apps.apple.com/app/streisand/id6450534064) (free). The parent design spec explicitly anticipates this — Channel B is desktop-side; mobile use is best-effort via existing VLESS clients for Channel A only.

Real Channel B iOS support would require building a native iOS client around upstream's gomobile bindings, plus solving the distribution problem (sideloading or alternative-app-store route). That's a separate, much larger phase — not in the Phase 4 backlog.

### What if the link doesn't come up for them

Common failure modes for the recipient:
- **No output / hangs at start** — wbstream might be blocked on their ISP (very rare, it's whitelisted; but possible on corporate/school networks). Try a different network.
- **`SOCKS5 server listening on 127.0.0.1:1080` but curl returns nothing** — initial WebRTC handshake still in progress; wait 15 s after seeing that line before curling.
- **Wrong IP in `ifconfig.me`** — they didn't actually route their browser through the SOCKS5; their proxy config is wrong.
- **Connection works briefly then dies** — Wildberries TURN allocation expired; restart the olcrtc client (it'll re-negotiate). For sustained sessions this is rare; for our v0 5-min test we saw zero disconnects.

Always recoverable: kill the olcrtc process and restart. No state to clean up on their machine.

---

## What this does NOT do

- **It is not a full VPN.** It's a SOCKS5 proxy. Apps that don't honor SOCKS or system proxy (some games, some IM clients, anything using raw sockets) bypass it. Use Option C (Brook tun2socks) if you need everything.
- **It does not hide that you're using SOCKS5 locally.** Anything on your machine can see `127.0.0.1:1080`. That's only a concern if you don't trust other processes on your own device.
- **It does not encrypt your TLS twice.** olcrtc adds its ChaCha20 layer between client and server. Your HTTPS to the destination still relies on normal TLS — same as without a VPN. No fewer or more padlocks.
- **It does not give Russian users a US/JP exit.** It gives them ZOV's NL exit. If they want a US/JP exit, that's Channel A (VLESS via Reality) or future channels.

## Quick reference

| Need | Command |
|---|---|
| Start server | `ssh ZenithOfVastness 'sudo systemctl start maskanya-olcrtc-bridge'` |
| Start local client | `./experiments/b-webrtc/scripts/run-client.sh` |
| Test tunnel | `curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me` |
| Stop client | Ctrl-C in client terminal |
| Stop server | `ssh ZenithOfVastness 'sudo systemctl stop maskanya-olcrtc-bridge'` |
| Full teardown on ZOV | `./experiments/b-webrtc/scripts/teardown-zov.sh` |
| Rebuild binaries | `./experiments/b-webrtc/scripts/build.sh` |

## What's coming next (Phase 4 backlog)

- **04-02** — Ansible role: enable-on-boot, no manual `systemctl start`. Channel B becomes always-on for the operator side.
- **04-03** — Companion app: a Tauri GUI that wraps the client. Russian recipients just install one app, paste a subscription URL, and pick "Channel B" from a dropdown. No PowerShell.
- **04-04** — Per-user keys via Marzban: each recipient gets their own Room+key derived from a JWT. Revoking one user no longer breaks all users.
- **04-05** — Fallback carriers (Telemost, SaluteJazz) so if Wildberries' SFU has a bad day, the channel auto-rotates.
