#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIROFISH_MCP_COMMAND="${MIROFISH_MCP_COMMAND:-$ROOT/../../mirofish-mcp-server/scripts/run-stdio.sh}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export BUZZ_SCENARIO_SURREAL_DB="${BUZZ_SCENARIO_SURREAL_DB:-buzz_mirofish_scenario}"
cd "$ROOT"
./scripts/run-buzz-desktop.sh --stop 2>/dev/null || true
exec ./scripts/run-buzz-desktop.sh
