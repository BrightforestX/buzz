#!/usr/bin/env bash
# One-time dev Keychain setup: allow-all ACL on buzz-desktop-dev so rebuilds
# do not re-prompt. Run after Buzz Dev has created the keychain blob once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=instance-env.sh
source "$SCRIPT_DIR/instance-env.sh" 2>/dev/null || true
# shellcheck source=lib/dev-keychain-acl.sh
source "$SCRIPT_DIR/lib/dev-keychain-acl.sh"

export BUZZ_DEV_KEYRING_SERVICE="${BUZZ_DEV_KEYRING_SERVICE:-$(dev_keychain_instance_service)}"
export BUZZ_KEYRING_SERVICE="${BUZZ_KEYRING_SERVICE:-$BUZZ_DEV_KEYRING_SERVICE}"

if [[ "$(uname)" != Darwin ]]; then
  echo "setup-dev-keychain-once: macOS only — skipping"
  exit 0
fi

NON_INTERACTIVE="${BUZZ_DEV_KEYCHAIN_SETUP_NON_INTERACTIVE:-0}"

echo "setup-dev-keychain-once: ensuring stable dev codesign identity…"
"$SCRIPT_DIR/ensure-dev-codesign-identity.sh" || true

configured_any=0
missing_any=0

while IFS= read -r service; do
  [[ -n "$service" ]] || continue

  if dev_keychain_allow_all_configured "$service"; then
    echo "setup-dev-keychain-once: allow-all already configured for $service"
    configured_any=1
    continue
  fi

  if ! dev_keychain_item_exists "$service"; then
    echo "setup-dev-keychain-once: skip — no $service item yet" >&2
    missing_any=1
    continue
  fi

  pw="$(dev_keychain_read_secret "$service")"
  if [[ -z "$pw" ]]; then
    echo "setup-dev-keychain-once: could not read $service — unlock login keychain and retry" >&2
    exit 1
  fi

  echo "setup-dev-keychain-once: applying allow-all ACL on $service (one login prompt may appear)…"
  if ! dev_keychain_apply_allow_all "$pw" "$service"; then
    echo "setup-dev-keychain-once: failed for $service — set ACL manually in Keychain Access" >&2
    exit 1
  fi
  configured_any=1

  bin=""
  if bin="$(dev_keychain_default_desktop_bin)"; then
    if dev_keychain_apply_binary_trust "$pw" "$bin" "$service"; then
      echo "setup-dev-keychain-once: also trusted $(basename "$bin") on $service"
    fi
  fi
done < <(dev_keychain_services_to_refresh)

if [[ "$configured_any" == "0" && "$missing_any" == "1" ]]; then
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    exit 0
  fi
  cat >&2 <<EOF
setup-dev-keychain-once: no dev Keychain items found yet.

Launch Buzz Desktop (dev) once and sign in so the secrets blob is created, then re-run:

  bash scripts/setup-dev-keychain-once.sh
EOF
  exit 1
fi

cat <<EOF
setup-dev-keychain-once: done.

Optional verification in Keychain Access:
  1. Open Keychain Access → login → search "buzz-desktop-dev"
  2. Double-click each dev entry (account: secrets), including buzz-desktop-dev.main
  3. Access Control → confirm "Allow all applications to access this item"

Quit and relaunch Buzz Desktop. Future cargo builds should not re-prompt for Keychain ACL changes.
EOF
