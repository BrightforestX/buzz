#!/usr/bin/env bash
# Sign buzz-desktop (debug) with the stable local dev identity.
set -euo pipefail

IDENTITY="${BUZZ_DEV_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "${HOME}/.config/buzz/dev-codesign-identity" ]]; then
  IDENTITY="$(<"${HOME}/.config/buzz/dev-codesign-identity")"
fi
BIN="${1:-}"

if [[ "$(uname)" != Darwin ]]; then
  exit 0
fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  exit 0
fi

# codesign accepts a 40-char SHA-1 hash to avoid ambiguous duplicate cert names.
if [[ ! "$IDENTITY" =~ ^[A-F0-9]{40}$ ]]; then
  echo "codesign-dev-desktop: skip — run scripts/ensure-dev-codesign-identity.sh first" >&2
  exit 0
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "codesign-dev-desktop: skip — identity $IDENTITY not in keychain" >&2
  exit 0
fi

TAURI_DIR="$(cd "$(dirname "$BIN")/../.." && pwd)"
ENTITLEMENTS="${BUZZ_DEV_ENTITLEMENTS:-$TAURI_DIR/Entitlements.plist}"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  ENTITLEMENTS="$(cd "$(dirname "$0")/../desktop/src-tauri" && pwd)/Entitlements.plist"
fi

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$BIN"
else
  codesign --force --sign "$IDENTITY" "$BIN"
fi

codesign --verify --verbose=2 "$BIN" >/dev/null
echo "codesign-dev-desktop: signed $BIN with identity $IDENTITY"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=instance-env.sh
source "$SCRIPT_DIR/instance-env.sh" 2>/dev/null || true
export BUZZ_DEV_KEYRING_SERVICE="${BUZZ_DEV_KEYRING_SERVICE:-buzz-desktop-dev.${BUZZ_INSTANCE_SLUG:-main}}"
export BUZZ_KEYRING_SERVICE="${BUZZ_KEYRING_SERVICE:-$BUZZ_DEV_KEYRING_SERVICE}"
"$SCRIPT_DIR/refresh-dev-keychain-acl.sh" "$BIN" || true
