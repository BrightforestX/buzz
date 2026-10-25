#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "========== Lane A (mock Playwright) =========="
pnpm exec vite build --mode e2e
pnpm exec playwright test agent-mcp-settings --project=smoke
cargo check --manifest-path src-tauri/Cargo.toml

echo "========== Lane B (Tauri WebDriver + self-test) =========="
node ./scripts/lane-b-self-test.mjs
export BUZZ_DESKTOP_WEBDRIVER="${BUZZ_DESKTOP_WEBDRIVER:-1}"
node ./scripts/tauri-webdriver-invoke-probe.mjs

echo "========== Lane C (Rust / agent MCP) =========="
./scripts/run-lane-c.sh

echo "All desktop test lanes (A, B, C) finished."
