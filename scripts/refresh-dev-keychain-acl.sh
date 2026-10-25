#!/usr/bin/env bash
# Idempotent Keychain ACL maintenance for buzz-desktop-dev after debug codesign.
#
# Default (allow-all): no-op when setup-dev-keychain-once.sh has run — avoids
# repeated "security wants to change access permissions" prompts on every build.
#
# binary-trust mode: append -T for the binary only when CDHash changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=instance-env.sh
source "$SCRIPT_DIR/instance-env.sh" 2>/dev/null || true
# shellcheck source=lib/dev-keychain-acl.sh
source "$SCRIPT_DIR/lib/dev-keychain-acl.sh"

BIN="${1:-}"
ACL_MODE="${BUZZ_DEV_KEYCHAIN_ACL_MODE:-allow-all}"
FORCE="${BUZZ_FORCE_KEYCHAIN_ACL_REFRESH:-0}"

if [[ "$(uname)" != Darwin ]]; then
  exit 0
fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  exit 0
fi

export BUZZ_DEV_KEYRING_SERVICE="${BUZZ_DEV_KEYRING_SERVICE:-$(dev_keychain_instance_service)}"
export BUZZ_KEYRING_SERVICE="${BUZZ_KEYRING_SERVICE:-$BUZZ_DEV_KEYRING_SERVICE}"

refreshed=0
while IFS= read -r service; do
  [[ -n "$service" ]] || continue
  if ! dev_keychain_item_exists "$service"; then
    continue
  fi

  if [[ "$FORCE" != "1" ]]; then
    if [[ "$ACL_MODE" == "allow-all" ]] && dev_keychain_allow_all_configured "$service"; then
      continue
    fi
    if [[ "$ACL_MODE" == "binary-trust" ]] && dev_keychain_cdhash_matches_cache "$BIN"; then
      continue
    fi
  fi

  pw="$(dev_keychain_read_secret "$service")"
  if [[ -z "$pw" ]]; then
    echo "refresh-dev-keychain-acl: could not read $service (keychain locked?)" >&2
    continue
  fi

  if [[ "$ACL_MODE" == "allow-all" ]]; then
    if dev_keychain_apply_allow_all "$pw" "$service"; then
      echo "refresh-dev-keychain-acl: allow-all ACL configured for $service"
      refreshed=1
    else
      echo "refresh-dev-keychain-acl: warn — could not apply allow-all for $service; run scripts/setup-dev-keychain-once.sh" >&2
    fi
    continue
  fi

  if [[ "$ACL_MODE" == "binary-trust" ]]; then
    if dev_keychain_apply_binary_trust "$pw" "$BIN" "$service"; then
      echo "refresh-dev-keychain-acl: updated binary trust for $(basename "$BIN") on $service"
      refreshed=1
    else
      echo "refresh-dev-keychain-acl: warn — could not update ACL for $service; fix manually in Keychain Access" >&2
    fi
  fi
done < <(dev_keychain_services_to_refresh)

if [[ "$refreshed" == "1" ]]; then
  exit 0
fi

if [[ "$ACL_MODE" == "allow-all" || "$ACL_MODE" == "binary-trust" ]]; then
  exit 0
fi

echo "refresh-dev-keychain-acl: unknown BUZZ_DEV_KEYCHAIN_ACL_MODE=$ACL_MODE (use allow-all or binary-trust)" >&2
exit 1
