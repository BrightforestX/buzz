#!/usr/bin/env bash
# Shared helpers for buzz-desktop-dev Keychain ACL (macOS dev only).
# Sourced by refresh-dev-keychain-acl.sh, setup-dev-keychain-once.sh, and tests.

dev_keychain_service() {
  if [[ -n "${BUZZ_KEYRING_SERVICE:-}" ]]; then
    printf '%s' "$BUZZ_KEYRING_SERVICE"
  elif [[ -n "${BUZZ_DEV_KEYRING_SERVICE:-}" ]]; then
    printf '%s' "$BUZZ_DEV_KEYRING_SERVICE"
  else
    printf '%s' "buzz-desktop-dev"
  fi
}

# Instance-scoped dev service (desktop-standalone default: buzz-desktop-dev.main).
dev_keychain_instance_service() {
  printf '%s' "buzz-desktop-dev.${BUZZ_INSTANCE_SLUG:-main}"
}

# Services that may hold secrets during dev (instance + legacy base).
dev_keychain_services_to_refresh() {
  local base="buzz-desktop-dev"
  local instance
  instance="$(dev_keychain_instance_service)"
  if [[ "$instance" == "$base" ]]; then
    printf '%s\n' "$base"
  else
    printf '%s\n' "$instance" "$base"
  fi
}

dev_keychain_service_slug() {
  local service="$1"
  printf '%s' "${service//./-}"
}

dev_keychain_account() {
  printf '%s' "secrets"
}

dev_keychain_config_dir() {
  printf '%s' "${BUZZ_DEV_KEYCHAIN_CONFIG_DIR:-${HOME}/.config/buzz}"
}

dev_keychain_cdhash_cache_path() {
  printf '%s' "$(dev_keychain_config_dir)/dev-keychain-acl-cdhash"
}

dev_keychain_allow_all_marker_path() {
  local service="${1:-$(dev_keychain_service)}"
  printf '%s' "$(dev_keychain_config_dir)/dev-keychain-allow-all.$(dev_keychain_service_slug "$service")"
}

# CDHash of a signed macOS binary (empty if unsigned or missing).
dev_keychain_cdhash() {
  local bin="$1"
  [[ -f "$bin" ]] || return 0
  codesign -dvvv "$bin" 2>&1 | sed -n 's/.*CDHash=\{0,1\}\([0-9A-Fa-f]*\).*/\1/p' | head -1
}

dev_keychain_item_exists() {
  local service="${1:-$(dev_keychain_service)}"
  local account
  account="$(dev_keychain_account)"
  security find-generic-password -s "$service" -a "$account" &>/dev/null
}

# True when one-time allow-all setup completed and the item is still present.
dev_keychain_allow_all_configured() {
  local service="${1:-$(dev_keychain_service)}"
  [[ -f "$(dev_keychain_allow_all_marker_path "$service")" ]] && dev_keychain_item_exists "$service"
}

dev_keychain_cdhash_matches_cache() {
  local bin="$1"
  local cdhash cache_path
  cdhash="$(dev_keychain_cdhash "$bin")"
  cache_path="$(dev_keychain_cdhash_cache_path)"
  [[ -n "$cdhash" && -f "$cache_path" && "$(<"$cache_path")" == "$cdhash" ]]
}

dev_keychain_write_cdhash_cache() {
  local bin="$1"
  local cdhash config_dir
  cdhash="$(dev_keychain_cdhash "$bin")"
  [[ -n "$cdhash" ]] || return 0
  config_dir="$(dev_keychain_config_dir)"
  mkdir -p "$config_dir"
  umask 077
  printf '%s\n' "$cdhash" >"$(dev_keychain_cdhash_cache_path)"
}

dev_keychain_read_secret() {
  local service="${1:-$(dev_keychain_service)}"
  local account
  account="$(dev_keychain_account)"
  security find-generic-password -s "$service" -a "$account" -w 2>/dev/null || true
}

# Write/update a generic-password item via Python so JSON blobs are not mangled
# by shell word-splitting. Uses -X hex; -A and -T are mutually exclusive on macOS.
dev_keychain_security_upsert() {
  local mode="$1"
  local pw="$2"
  local service="$3"
  local bin="${4:-}"
  python3 - "$mode" "$pw" "$service" "$(dev_keychain_account)" "$bin" <<'PY'
import subprocess
import sys

mode, password, service, account, bin_path = sys.argv[1:6]
hexpw = password.encode().hex()
cmd = [
    "security", "add-generic-password",
    "-a", account,
    "-s", service,
    "-U",
    "-X", hexpw,
]
if mode == "allow-all":
    cmd.append("-A")
elif mode == "trust" and bin_path:
    cmd.extend(["-T", bin_path])
else:
    sys.exit(2)

for keychain in (
    f"{__import__('os').path.expanduser('~/Library/Keychains/login.keychain-db')}",
    "login.keychain",
):
    attempt = cmd + [keychain]
    if subprocess.run(attempt, capture_output=True).returncode == 0:
        sys.exit(0)
sys.exit(1)
PY
}

# Apply allow-all ACL (-A). May prompt once for login keychain password.
dev_keychain_apply_allow_all() {
  local pw="$1"
  local service="${2:-$(dev_keychain_service)}"
  local config_dir marker
  config_dir="$(dev_keychain_config_dir)"
  marker="$(dev_keychain_allow_all_marker_path "$service")"

  if ! dev_keychain_security_upsert allow-all "$pw" "$service"; then
    return 1
  fi

  mkdir -p "$config_dir"
  umask 077
  date -u +%Y-%m-%dT%H:%M:%SZ >"$marker"
  return 0
}

# Apply per-binary trust (-T only). Updates CDHash cache on success.
dev_keychain_apply_binary_trust() {
  local pw="$1"
  local bin="$2"
  local service="${3:-$(dev_keychain_service)}"

  if dev_keychain_security_upsert trust "$pw" "$service" "$bin"; then
    dev_keychain_write_cdhash_cache "$bin"
    return 0
  fi
  return 1
}

dev_keychain_default_desktop_bin() {
  local root lib_dir
  if [[ -n "${BUZZ_ROOT:-}" ]]; then
    root="$BUZZ_ROOT"
  else
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    root="$(cd "$lib_dir/../.." && pwd)"
  fi
  for candidate in \
    "$root/desktop/src-tauri/target/debug/buzz-desktop" \
    "$root/target/debug/buzz-desktop"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}
