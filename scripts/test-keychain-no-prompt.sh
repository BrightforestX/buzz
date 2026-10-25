#!/usr/bin/env bash
# Quick manual test: rebuild buzz-agent 3x and optionally codesign buzz-desktop.
# Logs any `security add-generic-password` calls (the login-password prompt trigger).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRACE_LOG="${TMPDIR:-/tmp}/buzz-keychain-prompt-test.log"
MOCK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$MOCK_DIR"
}
trap cleanup EXIT

cat >"$MOCK_DIR/security" <<'EOF'
#!/usr/bin/env bash
LOG="${BUZZ_SECURITY_TRACE_LOG:?}"
printf '%s\n' "security $*" >>"$LOG"
if [[ "$1" == "add-generic-password" ]]; then
  printf '%s\n' "  >>> LOGIN PROMPT RISK: add-generic-password" >>"$LOG"
fi
exec /usr/bin/security "$@"
EOF
chmod +x "$MOCK_DIR/security"

export BUZZ_SECURITY_TRACE_LOG="$TRACE_LOG"
: >"$TRACE_LOG"
export PATH="$MOCK_DIR:${PATH}"

cd "$ROOT"

echo "=== buzz-desktop-dev keychain state ==="
if security find-generic-password -s buzz-desktop-dev -a secrets &>/dev/null; then
  echo "  item: present"
else
  echo "  item: missing (refresh is no-op until Buzz Desktop creates it)"
fi
if [[ -f "${HOME}/.config/buzz/dev-keychain-allow-all" ]]; then
  echo "  allow-all marker: set ($(cat "${HOME}/.config/buzz/dev-keychain-allow-all"))"
else
  echo "  allow-all marker: missing — run: bash scripts/setup-dev-keychain-once.sh"
fi

echo ""
echo "=== cargo build -p buzz-agent (x3) ==="
for i in 1 2 3; do
  echo "  build $i..."
  cargo build -p buzz-agent -q
done

BIN=""
for candidate in \
  "$ROOT/desktop/src-tauri/target/debug/buzz-desktop" \
  "$ROOT/target/debug/buzz-desktop"; do
  if [[ -f "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done

if [[ -n "$BIN" ]]; then
  echo ""
  echo "=== codesign-dev-desktop (desktop relink path) ==="
  bash "$ROOT/scripts/codesign-dev-desktop.sh" "$BIN" || true
else
  echo ""
  echo "=== skip codesign (no buzz-desktop binary) ==="
fi

echo ""
echo "=== security trace ($TRACE_LOG) ==="
if grep -q 'add-generic-password' "$TRACE_LOG" 2>/dev/null; then
  cat "$TRACE_LOG"
  echo ""
  echo "FAIL: add-generic-password was invoked — you may have seen a login-password dialog."
  echo "Fix: bash scripts/setup-dev-keychain-once.sh (once), then retry."
  exit 1
fi

if [[ -s "$TRACE_LOG" ]]; then
  cat "$TRACE_LOG"
else
  echo "(no security CLI calls during this test)"
fi

echo ""
echo "PASS: no add-generic-password calls. If macOS still prompted, it was outside this script (e.g. Buzz Desktop read)."
