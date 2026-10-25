#!/usr/bin/env bash
# Wait for buzz-desktop to finish linking, then codesign (macOS dev Keychain ACL).
set -euo pipefail

BIN="${1:-}"
SIGNER="${2:-}"

if [[ -z "$BIN" || -z "$SIGNER" || "$(uname)" != Darwin ]]; then
  exit 0
fi

start_sig=""
if [[ -f "$BIN" ]]; then
  start_sig="$(stat -f '%m:%z' "$BIN")"
fi

# Phase 1: wait for rustc to relink (mtime/size change) or for a new binary to appear.
changed=0
for _ in $(seq 1 240); do
  if [[ -f "$BIN" ]]; then
    sig="$(stat -f '%m:%z' "$BIN")"
    if [[ -z "$start_sig" || "$sig" != "$start_sig" ]]; then
      changed=1
      break
    fi
  fi
  sleep 0.25
done

# Phase 2: wait for the linked binary to stop changing.
last=""
stable=0
for _ in $(seq 1 40); do
  if [[ ! -f "$BIN" ]]; then
    sleep 0.25
    continue
  fi
  sig="$(stat -f '%m:%z' "$BIN")"
  if [[ "$sig" == "$last" ]]; then
    stable=$((stable + 1))
    if [[ $stable -ge 4 ]]; then
      exec "$SIGNER" "$BIN"
    fi
  else
    stable=0
    last="$sig"
  fi
  sleep 0.25
done

# If the binary never relinked, still sign the current debug artifact once.
if [[ -f "$BIN" ]]; then
  exec "$SIGNER" "$BIN"
fi

exit 0
