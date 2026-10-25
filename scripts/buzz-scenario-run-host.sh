#!/usr/bin/env bash
# Host scenario runner (loopback stack). Used by Buzz Tauri + live validation + Daytona driver payload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${ROOT}/../.." && pwd)"
CHAIN_MCP="${EXPERIMENTS_ROOT}/baseten-chain-mcp"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export ZEP_SHIM_BASE_URL="${ZEP_SHIM_BASE_URL:-http://127.0.0.1:8100/api/v2}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"
export BUZZ_SCENARIO_ENGINES="${BUZZ_SCENARIO_ENGINES:-mirofish}"

curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null || {
  echo "FAIL: MiroFish not reachable at ${MIROFISH_BASE_URL}" >&2
  exit 1
}
curl -sf "${SURREALDB_URL}/health" >/dev/null || {
  echo "FAIL: SurrealDB not reachable at ${SURREALDB_URL}" >&2
  exit 1
}

cd "${CHAIN_MCP}"
exec uv run python scripts/buzz-scenario-orchestrated-run.py
