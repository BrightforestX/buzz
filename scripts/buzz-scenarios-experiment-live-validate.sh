#!/usr/bin/env bash
# Formal live validation: unit tests, orchestrated host run, Daytona driver, Buzz green/red.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${ROOT}/../.." && pwd)"
CHAIN_MCP="${EXPERIMENTS_ROOT}/baseten-chain-mcp"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"

echo "== baseten-chain-mcp scenario unit tests =="
(cd "${CHAIN_MCP}" && uv run pytest tests/scenario/test_surreal_trino_seed.py tests/scenario/test_mirofish_experiment_store.py -q)

echo "== host orchestrated scenario (Surreal + MiroFish + graph snapshot) =="
"${ROOT}/scripts/buzz-scenario-run-host.sh"

echo "== Phase B Daytona driver (host required; cloud optional) =="
"${ROOT}/scripts/buzz-scenarios-daytona-experiment-driver.sh"

echo "== Buzz Scenarios green/red (compile, UI tests, stack probes) =="
"${ROOT}/scripts/buzz-scenarios-workflows-green-red.sh"

echo "== validation complete =="
