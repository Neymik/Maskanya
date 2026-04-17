#!/usr/bin/env bash
# Pre-commit guard: refuse to let plaintext secrets reach git.
#
# Passes when every file under secrets/ contains the SOPS metadata block.
# Also scans the full staged diff for obvious private-key headers and AGE secret keys.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

FAIL=0

# 1. Every secrets/*.yml must be SOPS-encrypted.
if [ -d secrets ]; then
  for f in secrets/*.yml secrets/*.yaml; do
    [ -f "$f" ] || continue
    if ! grep -q '^sops:' "$f"; then
      echo "ERROR: $f is not SOPS-encrypted (missing 'sops:' footer)." >&2
      FAIL=1
    fi
  done
fi

# 2. Scan staged changes for private-key material that should never be committed.
STAGED="$(git diff --cached --name-only --diff-filter=ACM || true)"
for f in $STAGED; do
  [ -f "$f" ] || continue
  # Skip the encrypted files themselves; they legitimately contain the literal
  # string "ENC[" and "age-encryption.org" but never unencrypted markers.
  if [[ "$f" == secrets/* ]] && grep -q '^sops:' "$f"; then
    continue
  fi
  if grep -E -q 'BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY' "$f"; then
    echo "ERROR: $f contains a private-key PEM header." >&2
    FAIL=1
  fi
  if grep -E -q 'AGE-SECRET-KEY-1[0-9A-Z]{58}' "$f"; then
    echo "ERROR: $f contains an AGE secret key." >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "" >&2
  echo "Plaintext-secrets check failed. Encrypt with:" >&2
  echo "  SOPS_AGE_KEY_FILE=~/.config/sops/age/maskanya.txt sops -e -i <file>" >&2
  exit 1
fi
