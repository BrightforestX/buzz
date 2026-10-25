#!/usr/bin/env bash
# Automated red/green for Buzz Scenarios new features (unit + integration + live gates).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESKTOP="${BUZZ_ROOT}/desktop"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
CHAIN_MCP="${EXPERIMENTS_ROOT}/baseten-chain-mcp"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"

echo "== [automated] baseten-chain-mcp scenario pytest =="
(cd "${CHAIN_MCP}" && uv run pytest tests/scenario/ -q)

echo "== [automated] Buzz desktop scenarios node tests =="
(cd "${DESKTOP}" && node --import ./test-loader.mjs --experimental-strip-types --test \
  "src/features/scenarios/**/*.test.mjs")

echo "== [automated] Buzz desktop compile + mirofish_scenario guards =="
if [[ "$(uname -s)" == "Darwin" ]]; then
  export CARGO="${BUZZ_ROOT}/scripts/cargo-dev-wrapper/cargo"
  export PATH="${BUZZ_ROOT}/scripts/cargo-dev-wrapper:${PATH}"
  export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="${BUZZ_ROOT}/scripts/dev-macos-linker.sh"
  export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="${BUZZ_ROOT}/scripts/dev-macos-linker.sh"
fi
(cd "${DESKTOP}/src-tauri" && cargo check -p buzz-desktop)

echo "== [automated] live stack + green/red probe script =="
"${BUZZ_ROOT}/scripts/buzz-scenarios-experiment-live-validate.sh"

echo "== automated red/green: PASS =="
