#!/usr/bin/env bash
# Export BUZZ_PRIVATE_KEY + BUZZ_RELAY_URL for pathx CLI without repeated macOS
# Keychain prompts. On first use, reads buzz-desktop-dev once and caches to
# ~/.config/buzz/dev-relay-identity (mode 0600). Safe to source from ~/.zshrc.
#
# Usage:
#   source scripts/relay-env.sh
#   buzz channels list

set -euo pipefail

export BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-wss://pathx.communities.buzz.xyz}"

if [[ -n "${BUZZ_PRIVATE_KEY:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

CACHE="${BUZZ_RELAY_IDENTITY_CACHE:-${HOME}/.config/buzz/dev-relay-identity}"
KEYRING_SERVICE="${BUZZ_KEYRING_SERVICE:-buzz-desktop-dev}"

_read_identity_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local key
  key="$(<"$path")"
  key="${key//$'\n'/}"
  key="${key//$'\r'/}"
  [[ -n "$key" ]] || return 1
  printf '%s' "$key"
}

_cache_identity() {
  local key="$1"
  umask 077
  mkdir -p "$(dirname "$CACHE")"
  printf '%s' "$key" >"$CACHE"
  chmod 600 "$CACHE"
}

_resolve_from_keychain() {
  command -v security >/dev/null 2>&1 || return 1
  local blob key
  blob="$(security find-generic-password -s "$KEYRING_SERVICE" -a secrets -w 2>/dev/null || true)"
  [[ -n "$blob" ]] || return 1
  key="$(printf '%s' "$blob" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("identity",""); print(v if isinstance(v,str) else "")' 2>/dev/null || true)"
  [[ -n "$key" ]] || return 1
  printf '%s' "$key"
}

# 1) Cached CLI identity (no keychain)
if key="$(_read_identity_file "$CACHE" 2>/dev/null)"; then
  export BUZZ_PRIVATE_KEY="$key"
  return 0 2>/dev/null || exit 0
fi

# 2) Buzz Dev identity.key fallback (no keychain)
for candidate in \
  "${HOME}/Library/Application Support/xyz.block.buzz.app.dev/identity.key" \
  "${HOME}/Library/Application Support/xyz.block.sprout.app.dev/identity.key"; do
  if key="$(_read_identity_file "$candidate" 2>/dev/null)"; then
    _cache_identity "$key"
    export BUZZ_PRIVATE_KEY="$key"
    echo "relay-env: cached identity from $(basename "$(dirname "$candidate")") → $CACHE" >&2
    return 0 2>/dev/null || exit 0
  fi
done

# 3) One-time keychain read → cache (last resort; may prompt once)
if key="$(_resolve_from_keychain)"; then
  _cache_identity "$key"
  export BUZZ_PRIVATE_KEY="$key"
  echo "relay-env: cached identity from keychain → $CACHE (future shells skip keychain)" >&2
  return 0 2>/dev/null || exit 0
fi

echo "relay-env: could not resolve BUZZ_PRIVATE_KEY (open Buzz Dev once or run: security find-generic-password -s $KEYRING_SERVICE -a secrets -w)" >&2
return 1 2>/dev/null || exit 1
