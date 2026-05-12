#!/usr/bin/env bash
# Build olcrtc for ZOV (linux-amd64) and operator workstation (host platform).
# Can be run from anywhere — resolves repo root via git.

set -euo pipefail

# Ensure go-installed binaries (mage) are reachable even if ~/go/bin isn't on PATH globally.
export PATH="$HOME/go/bin:$PATH"

ROOT="$(git rev-parse --show-toplevel)"
UPSTREAM="$ROOT/experiments/b-webrtc/upstream"
OUTDIR="$ROOT/experiments/b-webrtc/build"

test -d "$UPSTREAM" || { echo "FATAL: $UPSTREAM missing — run Task 2 first." >&2; exit 1; }

mkdir -p "$OUTDIR"
cd "$UPSTREAM"

# mage cross builds 9 platforms; we only keep linux-amd64 + host.
go mod download
mage cross

HOST_OS=$(go env GOOS)
HOST_ARCH=$(go env GOARCH)

cp -v "build/olcrtc-linux-amd64"             "$OUTDIR/maskanya-olcrtc-linux-amd64"
cp -v "build/olcrtc-${HOST_OS}-${HOST_ARCH}" "$OUTDIR/maskanya-olcrtc-${HOST_OS}-${HOST_ARCH}"
chmod +x "$OUTDIR"/maskanya-olcrtc-*

echo
echo "Built:"
ls -la "$OUTDIR/"
