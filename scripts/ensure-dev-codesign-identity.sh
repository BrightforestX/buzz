#!/usr/bin/env bash
# Pick a stable macOS codesign identity hash for debug buzz-desktop rebuilds.
set -euo pipefail

CACHE="${HOME}/.config/buzz/dev-codesign-identity"
mkdir -p "$(dirname "$CACHE")"

if [[ "$(uname)" != Darwin ]]; then
  exit 0
fi

pick_identity_hash() {
  if [[ -n "${BUZZ_DEV_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$BUZZ_DEV_CODESIGN_IDENTITY"
    return 0
  fi
  if [[ -f "$CACHE" ]]; then
    local cached
    cached="$(<"$CACHE")"
    if [[ "$cached" =~ ^[A-F0-9]{40}$ ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$cached"; then
      printf '%s' "$cached"
      return 0
    fi
  fi
  local line hash
  line="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development:' | head -1 || true)"
  if [[ -n "$line" ]]; then
    hash="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) .*/\1/')"
    if [[ -n "$hash" ]]; then
      printf '%s' "$hash"
      return 0
    fi
  fi
  line="$(security find-identity -v -p codesigning 2>/dev/null | grep -E '^[[:space:]]*[0-9]+\)' | head -1 || true)"
  if [[ -n "$line" ]]; then
    hash="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) .*/\1/')"
    if [[ -n "$hash" ]]; then
      printf '%s' "$hash"
      return 0
    fi
  fi
  return 1
}

if hash="$(pick_identity_hash)"; then
  umask 077
  printf '%s\n' "$hash" >"$CACHE"
  chmod 600 "$CACHE"
  name="$(security find-identity -v -p codesigning 2>/dev/null | grep "$hash" | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
  echo "ensure-dev-codesign-identity: using ${name:-$hash}"
else
  echo "ensure-dev-codesign-identity: no codesign identity found — install Xcode / Apple Development cert" >&2
  exit 1
fi

BUZZ_BIN="${BUZZ_DEV_DESKTOP_BIN:-}"
if [[ -z "$BUZZ_BIN" ]]; then
  for candidate in \
    "$(cd "$(dirname "$0")/.." && pwd)/desktop/src-tauri/target/debug/buzz-desktop" \
    "$(cd "$(dirname "$0")/.." && pwd)/target/debug/buzz-desktop"; do
    if [[ -f "$candidate" ]]; then
      BUZZ_BIN="$candidate"
      break
    fi
  done
fi

if [[ -n "$BUZZ_BIN" && -f "$BUZZ_BIN" ]]; then
  "$(cd "$(dirname "$0")" && pwd)/refresh-dev-keychain-acl.sh" "$BUZZ_BIN" || true
fi
