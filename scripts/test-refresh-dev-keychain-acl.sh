#!/usr/bin/env bash
# Shell tests for dev Keychain ACL skip logic (mocked security/codesign).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$SCRIPT_DIR/lib/dev-keychain-acl.sh"
REFRESH="$SCRIPT_DIR/refresh-dev-keychain-acl.sh"

TMP=""
MOCK_BIN=""
MOCK_DIR=""
PASS=0
FAIL=0

cleanup() {
  [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $desc (expected=$expected actual=$actual)" >&2
  fi
}

assert_exit_0() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  ok  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $desc (non-zero exit)" >&2
  fi
}

setup_mocks() {
  TMP="$(mktemp -d)"
  MOCK_DIR="$TMP/mock-bin"
  mkdir -p "$MOCK_DIR" "$TMP/config/buzz"

  export BUZZ_DEV_KEYCHAIN_CONFIG_DIR="$TMP/config/buzz"
  export BUZZ_INSTANCE_SLUG="test"
  export BUZZ_DEV_KEYRING_SERVICE="buzz-desktop-dev.test"
  export BUZZ_KEYRING_SERVICE="buzz-desktop-dev.test"
  export HOME="$TMP/fake-home"
  mkdir -p "$HOME/Library/Keychains"

  MOCK_BIN="$TMP/fake-buzz-desktop"
  printf 'fake-binary' >"$MOCK_BIN"
  chmod +x "$MOCK_BIN"

  cat >"$MOCK_DIR/codesign" <<'EOF'
#!/usr/bin/env bash
echo "CDHash=FAKECDHASH1234567890ABCDEF1234567890AB"
EOF
  chmod +x "$MOCK_DIR/codesign"

  cat >"$MOCK_DIR/security" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  find-generic-password)
    if [[ " $* " == *" -w "* ]]; then
      printf '%s' '{"identity":"nsec1test"}'
    fi
    exit 0
    ;;
  add-generic-password)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$MOCK_DIR/security"

  export PATH="$MOCK_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  # shellcheck source=lib/dev-keychain-acl.sh
  source "$LIB"
}

run_refresh() {
  BUZZ_DEV_KEYCHAIN_ACL_MODE="${BUZZ_DEV_KEYCHAIN_ACL_MODE:-allow-all}" \
    "$REFRESH" "$MOCK_BIN"
}

test_allow_all_configured_skips_refresh() {
  echo "test_allow_all_configured_skips_refresh"
  setup_mocks
  while IFS= read -r service; do
    [[ -n "$service" ]] || continue
    date -u +%Y-%m-%dT%H:%M:%SZ >"$(dev_keychain_allow_all_marker_path "$service")"
  done < <(dev_keychain_services_to_refresh)
  local out
  out="$(run_refresh 2>&1 || true)"
  assert_eq "refresh silent when allow-all marker set" "" "$out"
}

test_cdhash_cache_skips_binary_trust() {
  echo "test_cdhash_cache_skips_binary_trust"
  setup_mocks
  dev_keychain_write_cdhash_cache "$MOCK_BIN"
  local out
  out="$(BUZZ_DEV_KEYCHAIN_ACL_MODE=binary-trust run_refresh 2>&1 || true)"
  assert_eq "binary-trust silent when CDHash cached" "" "$out"
}

test_cdhash_cache_write_and_match() {
  echo "test_cdhash_cache_write_and_match"
  setup_mocks
  dev_keychain_write_cdhash_cache "$MOCK_BIN"
  assert_eq "cdhash cache matches" "true" "$(dev_keychain_cdhash_matches_cache "$MOCK_BIN" && echo true || echo false)"
}

test_allow_all_marker_requires_item() {
  echo "test_allow_all_marker_requires_item"
  setup_mocks
  date -u +%Y-%m-%dT%H:%M:%SZ >"$(dev_keychain_allow_all_marker_path "buzz-desktop-dev.test")"
  # Override security to simulate missing item
  cat >"$MOCK_DIR/security" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCK_DIR/security"
  assert_eq "allow-all not configured without keychain item" "false" "$(dev_keychain_allow_all_configured && echo true || echo false)"
}

test_missing_item_refresh_noop() {
  echo "test_missing_item_refresh_noop"
  setup_mocks
  cat >"$MOCK_DIR/security" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCK_DIR/security"
  assert_exit_0 "refresh exits 0 when item missing" run_refresh
}

echo "=== test-refresh-dev-keychain-acl ==="
test_allow_all_configured_skips_refresh
test_cdhash_cache_skips_binary_trust
test_cdhash_cache_write_and_match
test_allow_all_marker_requires_item
test_missing_item_refresh_noop

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
