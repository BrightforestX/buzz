#!/usr/bin/env bash
# Trino (Docker) + SurrealDB → seeded scenario context for Buzz agents + MiroFish discussions.
# Optional OpenAPI catalog on OPENAPI_TRINO_HOST (8081) via openapi_trino_to_surreal.py.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
CHAIN="${EXPERIMENTS_ROOT}/baseten-chain-mcp"
SCENARIO_ID="${BUZZ_SCENARIO_ID:-buzz_mirofish_scenario}"
SURREAL_DB="${BUZZ_SCENARIO_SURREAL_DB:-${SCENARIO_ID}}"
OPENAPI_SURREAL_DB="${BUZZ_OPENAPI_SURREAL_DB:-buzz_openapi_context}"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"

cd "$BUZZ_ROOT"

echo "== Docker: Trino + SurrealDB (buzz-stack compose) =="
if [[ "${BUZZ_STACK_SKIP_DOCKER:-0}" == "1" ]]; then
  echo "SKIP docker up (BUZZ_STACK_SKIP_DOCKER=1)"
else
  cd "$BUZZ_ROOT"
  docker compose -f docker-compose.buzz-stack.yml up -d trino surrealdb
fi

echo "== Seed Iceberg pm_sim in Trino =="
export TRINO_HOST
export TRINO_USER="${TRINO_USER:-trino}"
export TRINO_CATALOG="${TRINO_CATALOG:-iceberg}"
export TRINO_SCHEMA="${TRINO_SCHEMA:-pm_sim}"
(
  cd "${EXPERIMENTS_ROOT}/baseten-chain-mcp"
  uv run python scripts/trino-seed-pm-sim.py
)

echo "== Trino pm_issues → Surreal (${SCENARIO_SURREAL_NS}/${SURREAL_DB}) =="
(
  cd "${EXPERIMENTS_ROOT}/baseten-chain-mcp"
  uv run python scripts/trino_jsonl_to_surreal.py \
    --query "SELECT * FROM iceberg.pm_sim.pm_issues" \
    --jsonl-path "${BUZZ_ROOT}/tmp/buzz_pm_issues.jsonl" \
    --ns "$SCENARIO_SURREAL_NS" \
    --db "$SURREAL_DB" \
    --table pm_issue
)

if [[ "${BUZZ_SCENARIO_GRAPH_SEED:-0}" == "1" ]]; then
  echo "== Trino → Surreal graph (scenario ${SCENARIO_ID}; Falkor optional) =="
  uv run python scripts/trino-seed-graphs.py \
    --scenario-id "$SCENARIO_ID" \
    --skip-trino-ddl \
    --surreal-only || echo "WARN: scenario graph seed skipped or failed (pm_issue JSONL seed may suffice)"
else
  echo "SKIP scenario graph seed (set BUZZ_SCENARIO_GRAPH_SEED=1 to run trino-seed-graphs.py --surreal-only)"
fi

if [[ -n "${OPENAPI_TRINO_HOST:-}" ]]; then
  echo "== OpenAPI Trino (${OPENAPI_TRINO_HOST}) → Surreal ${OPENAPI_SURREAL_DB} =="
  uv run python scripts/openapi_trino_to_surreal.py \
    --trino-host "$OPENAPI_TRINO_HOST" \
    --db "$OPENAPI_SURREAL_DB"
else
  echo "SKIP OpenAPI export (set OPENAPI_TRINO_HOST=http://127.0.0.1:8081 to enable)"
fi

echo "== Stack ready =="
echo "  TRINO_HOST=$TRINO_HOST"
echo "  SURREALDB_URL=$SURREALDB_URL"
echo "  scenario surreal db: ${SCENARIO_SURREAL_NS}/${SURREAL_DB}"
echo "  MIROFISH graph fixture: graph_mcp_eval_fixture @ $MIROFISH_BASE_URL"
echo "  Buzz UI: #/scenarios?graphId=graph_mcp_eval_fixture&scenarioDb=${SURREAL_DB}"
