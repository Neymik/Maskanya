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
