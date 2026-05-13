#!/usr/bin/env bash
# Package olcrtc client + .env + a wrapper into a single archive per platform.
# Output: experiments/b-webrtc/kits/maskanya-channel-b-<platform>.{zip,tar.gz}
#
# Recipients unzip/untar, run the launcher (run.bat / run.sh), point their
# browser at SOCKS5 127.0.0.1:1080. No PowerShell, no env-file handling.
#
# SECURITY: every kit contains the shared ChaCha20 key + Room ID baked into
# the launcher script. Treat each kit as a one-time-use secret bundle. Ship
# only via E2E channels (Signal / Magic Wormhole / encrypted ZIP).

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_FILE="experiments/b-webrtc/.env.olcrtc-v0"
UPSTREAM_BUILD="experiments/b-webrtc/upstream/build"
KITS="experiments/b-webrtc/kits"

test -f "$ENV_FILE" || { echo "FATAL: $ENV_FILE missing — run Task 4." >&2; exit 1; }
test -d "$UPSTREAM_BUILD" || { echo "FATAL: $UPSTREAM_BUILD missing — run scripts/build.sh." >&2; exit 1; }

# Load secrets (the wrapper bakes them in).
# shellcheck disable=SC1090
source "$ENV_FILE"

# What platforms to build. Override with arg list, e.g. ./build-kit.sh windows-amd64
PLATFORMS=("${@:-windows-amd64 linux-amd64 linux-arm64 darwin-arm64 darwin-amd64}")
mkdir -p "$KITS"

readme_common() {
cat <<'README'
Maskanya — Channel B (olcRTC over wbstream)
============================================

WHAT THIS IS
  A tunnel that lets you browse the web via a Netherlands server. Your traffic
  is wrapped inside what looks like a Wildberries live-stream session, so it
  uses an unblockable whitelisted Russian service as the transport.

QUICK START
  1. Unpack this folder anywhere (e.g., your Downloads).
  2. Run the launcher (see "How to start" below). A console window opens.
  3. Leave the console window open while you want the tunnel active.
  4. Configure your browser to use SOCKS5 127.0.0.1:1080 (instructions below).
  5. Open https://ifconfig.me — it should show 103.137.249.134 (NL).
  6. Close the console window when done.

CONFIGURE FIREFOX (RECOMMENDED, ONE-APP SCOPE)
  Settings -> search "proxy" -> Network Settings -> Settings...
    o Manual proxy configuration
    o SOCKS Host: 127.0.0.1     Port: 1080
    o SOCKS v5
    o (check) Proxy DNS when using SOCKS v5
  Apply. Visit https://ifconfig.me to verify. To turn off later: same screen,
  No proxy.

CONFIGURE THE WHOLE SYSTEM (Windows: Settings -> Network -> Proxy)
  Use a SOCKS proxy:  Address 127.0.0.1   Port 1080   Save.
  Some apps may still bypass it. Firefox above is more reliable.

CONFIGURE THE WHOLE SYSTEM (macOS)
  System Settings -> Network -> [interface] -> Details -> Proxies
  Enable "SOCKS Proxy": Server 127.0.0.1   Port 1080. Apply.

TROUBLESHOOTING
  - Browser shows your original IP -> proxy not actually configured.
  - Page hangs or never loads -> wait 15 seconds after starting (initial
    WebRTC handshake), then retry.
  - "Connection refused" -> the launcher window isn't running.
  - Slow/intermittent -> normal for the first 30 seconds while WebRTC settles.

LIMITATIONS
  - Only one device can use this kit at a time (the operator may also be
    online; coordinate). True multi-user comes in a later version.
  - This is NOT a system-wide VPN by default — it's a SOCKS5 proxy. Apps
    that don't honor the system proxy bypass it. Use Firefox to be sure.
  - Mobile (Android via Termux is possible; iOS is not supported in v0).

SECURITY
  - This kit contains a shared encryption key. Anyone with the kit can
    decrypt traffic in this room. Do NOT share the kit with others.
  - The egress IP (103.137.249.134, Netherlands) is a Maskanya VPS.
    HTTPS still ends at the destination as normal.

QUESTIONS
  Reply on the same channel you received this kit.
README
}

build_unix() {
  local platform="$1" arch="$2" os_label="$3" bin_src="$4"
  local kit="$KITS/maskanya-channel-b-${platform}"
  rm -rf "$kit" 2>/dev/null || true
  mkdir -p "$kit"

  cp "$bin_src" "$kit/olcrtc"
  chmod +x "$kit/olcrtc"

  cat > "$kit/run.sh" <<EOF
#!/usr/bin/env bash
# Maskanya Channel B launcher (${os_label}).
# Leaves a foreground process running until Ctrl-C.
set -euo pipefail
cd "\$(dirname "\$0")"
mkdir -p data

echo "=================================================="
echo "  Maskanya Channel B — starting"
echo "  SOCKS5 will be at  127.0.0.1:1080"
echo "  Configure your browser per README.txt"
echo "  Press Ctrl-C to stop."
echo "=================================================="
echo

exec ./olcrtc \\
  -mode cnc \\
  -carrier $OLCRTC_CARRIER \\
  -transport $OLCRTC_TRANSPORT \\
  -id $OLCRTC_ROOM_ID \\
  -client-id $OLCRTC_CLIENT_ID \\
  -key $OLCRTC_KEY \\
  -link direct \\
  -dns 1.1.1.1:53 \\
  -data ./data \\
  -socks-host 127.0.0.1 \\
  -socks-port 1080
EOF
  chmod +x "$kit/run.sh"

  {
    echo "Maskanya Channel B kit — $os_label / $arch"
    echo "Built: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "HOW TO START"
    echo "  1. Open a Terminal in this folder."
    echo "  2. ./run.sh"
    echo "     (on macOS the first run may prompt — Right-click -> Open to bypass Gatekeeper)"
    echo "  3. Leave the terminal open."
    echo
    readme_common
  } > "$kit/README.txt"

  (cd "$KITS" && tar czf "maskanya-channel-b-${platform}.tar.gz" "maskanya-channel-b-${platform}")
  echo "  -> $KITS/maskanya-channel-b-${platform}.tar.gz  ($(du -h "$KITS/maskanya-channel-b-${platform}.tar.gz" | awk '{print $1}'))"
}

build_windows() {
  local platform="windows-amd64"
  local bin_src="$UPSTREAM_BUILD/olcrtc-windows-amd64.exe"
  local kit="$KITS/maskanya-channel-b-${platform}"
  rm -rf "$kit" 2>/dev/null || true
  mkdir -p "$kit"

  cp "$bin_src" "$kit/olcrtc.exe"

  # CRLF line endings for Windows .bat compatibility.
  cat > "$kit/run.bat" <<EOF
@echo off
REM Maskanya Channel B launcher (Windows).
REM Leave this window open while using the tunnel. Close to stop.
setlocal
cd /d "%~dp0"
if not exist data mkdir data

echo ==================================================
echo   Maskanya Channel B - starting
echo   SOCKS5 will be at  127.0.0.1:1080
echo   Configure your browser per README.txt
echo   Press Ctrl-C or close this window to stop.
echo ==================================================
echo.

olcrtc.exe ^
  -mode cnc ^
  -carrier $OLCRTC_CARRIER ^
  -transport $OLCRTC_TRANSPORT ^
  -id $OLCRTC_ROOM_ID ^
  -client-id $OLCRTC_CLIENT_ID ^
  -key $OLCRTC_KEY ^
  -link direct ^
  -dns 1.1.1.1:53 ^
  -data data ^
  -socks-host 127.0.0.1 ^
  -socks-port 1080

pause
EOF
  # Convert to CRLF for proper Windows display.
  perl -pi -e 's/\n/\r\n/' "$kit/run.bat"

  {
    echo "Maskanya Channel B kit — Windows / amd64"
    echo "Built: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "HOW TO START"
    echo "  Double-click run.bat. A console window opens. Leave it open"
    echo "  while you want the tunnel running. Close the window to stop."
    echo "  Windows may warn 'unknown publisher' — click More info -> Run anyway."
    echo
    readme_common
  } | perl -pe 's/\n/\r\n/' > "$kit/README.txt"

  (cd "$KITS" && zip -rq "maskanya-channel-b-${platform}.zip" "maskanya-channel-b-${platform}")
  echo "  -> $KITS/maskanya-channel-b-${platform}.zip  ($(du -h "$KITS/maskanya-channel-b-${platform}.zip" | awk '{print $1}'))"
}

echo "Building kits for: ${PLATFORMS[*]}"
echo

for p in ${PLATFORMS[*]}; do
  echo "[$p]"
  case "$p" in
    windows-amd64) build_windows ;;
    linux-amd64)   build_unix "$p" "amd64"   "Linux"             "$UPSTREAM_BUILD/olcrtc-linux-amd64" ;;
    linux-arm64)   build_unix "$p" "arm64"   "Linux (ARM)"       "$UPSTREAM_BUILD/olcrtc-linux-arm64" ;;
    darwin-arm64)  build_unix "$p" "arm64"   "macOS Apple Silicon" "$UPSTREAM_BUILD/olcrtc-darwin-arm64" ;;
    darwin-amd64)  build_unix "$p" "amd64"   "macOS Intel"       "$UPSTREAM_BUILD/olcrtc-darwin-amd64" ;;
    *) echo "  ! unknown platform: $p (skipping)" ;;
  esac
done

echo
echo "Done. Kits at $KITS/"
echo "Ship via E2E channel only (Signal / Magic Wormhole / encrypted ZIP)."
