#!/usr/bin/env bash
# docker compose -f docker-compose.buzz-stack.yml up -d + wait + Surreal seed.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="${BUZZ_ROOT}/docker-compose.buzz-stack.yml"
SEED="${BUZZ_ROOT}/scripts/ensure-scenario-data-stack.sh"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"

MIROFISH_ENV="${BUZZ_ROOT}/../../MiroFish/.env"
if [[ -f "$MIROFISH_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$MIROFISH_ENV"
  set +a
fi
export MIROFISH_LLM_API_KEY="${LLM_API_KEY:-${BASETEN_API_KEY:-local}}"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker Desktop first." >&2
  exit 1
fi

cd "$BUZZ_ROOT"
echo "== docker compose up -d (buzz-stack) =="
docker compose -f "$COMPOSE" pull mirofish 2>/dev/null || true
docker compose -f "$COMPOSE" build zep-shim
docker compose -f "$COMPOSE" up -d

echo "== wait for health =="
for i in $(seq 1 120); do
  ok=0
  curl -sf "${TRINO_HOST}/v1/info" >/dev/null && ok=$((ok + 1))
  curl -sf "${SURREALDB_URL}/health" >/dev/null && ok=$((ok + 1))
  curl -sf http://127.0.0.1:8100/healthz >/dev/null && ok=$((ok + 1))
  curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null && ok=$((ok + 1))
  if [[ "$ok" -ge 4 ]]; then
    echo "all core services ready (${i}s)"
    break
  fi
  sleep 2
done

echo "== seed Trino → Surreal (host uv; skips duplicate docker up) =="
BUZZ_STACK_SKIP_DOCKER=1 "$SEED"

echo "== seed MiroFish graph fixture (zep-shim + Ollama) =="
if python3 "${BUZZ_ROOT}/scripts/seed-mirofish-graph-fixture.py"; then
  echo "graph fixture seed: ok"
else
  echo "WARN: graph fixture seed failed (Ollama on :11434? zep-shim logs?)"
fi

if curl -sf "${MIROFISH_BASE_URL}/api/graph/data/graph_mcp_eval_fixture" | rg -q '"nodes"'; then
  echo "graph_mcp_eval_fixture: ok"
else
  echo "WARN: graph_mcp_eval_fixture not ready (zep/LLM on host?)"
fi

echo "Buzz Scenarios: #/scenarios?graphId=graph_mcp_eval_fixture"
