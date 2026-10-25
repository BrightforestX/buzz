#!/usr/bin/env bash
# Lane C — Rust / agent MCP (no Playwright UI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUZZ_ROOT="$(cd "$ROOT/.." && pwd)"

fail() { echo "Lane C FAIL: $*" >&2; exit 1; }

echo "=== Lane C green: desktop Rust compiles (MCP commands) ==="
cargo check --manifest-path "$ROOT/src-tauri/Cargo.toml"

echo "=== Lane C green: buzz-agent live MCP smoke (MIROFISH_BUZZ_SMOKE=1) ==="
cd "$BUZZ_ROOT"
export MIROFISH_BUZZ_SMOKE=1
cargo test -p buzz-agent --test mirofish_mcp_smoke

echo "=== Lane C red: live MCP smoke gated off without MIROFISH_BUZZ_SMOKE ==="
unset MIROFISH_BUZZ_SMOKE
red_out="$(cargo test -p buzz-agent mirofish_mcp_session_new_succeeds -- --nocapture 2>&1)" || true
echo "$red_out" | grep -q "skip mirofish_mcp_session" \
  || fail "expected skip without MIROFISH_BUZZ_SMOKE; got: $red_out"

echo "=== Lane C note: buzz-desktop lib unit tests (mcp_settings::tests) ==="
echo "Run on CI/Linux or after linking libopus: cargo test --manifest-path $ROOT/src-tauri/Cargo.toml mcp_settings::tests --lib"

echo "Lane C finished OK."
