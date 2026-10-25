#!/usr/bin/env bash
# Scenario stack for Buzz Scenarios tab: Docker Trino + Surreal, seed, zep-shim, MiroFish.
# Intended for a dedicated Terminal tab (Hermit toolchain optional).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
LOG="${BUZZ_ROOT}/.local/scenario-stack-herd.log"

mkdir -p "${BUZZ_ROOT}/.local"
exec > >(tee -a "$LOG") 2>&1

if [[ -f "${BUZZ_ROOT}/bin/activate-hermit" ]]; then
  # shellcheck disable=SC1091
  . "${BUZZ_ROOT}/bin/activate-hermit"
fi

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export ZEP_SHIM_BASE_URL="${ZEP_SHIM_BASE_URL:-http://127.0.0.1:8100/api/v2}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export BUZZ_SCENARIO_SURREAL_DB="${BUZZ_SCENARIO_SURREAL_DB:-buzz_mirofish_scenario}"
export BUZZ_SCENARIO_ID="${BUZZ_SCENARIO_ID:-buzz_mirofish_scenario}"

echo "===== scenario stack herd $(date -Iseconds) ====="
echo "Log: ${LOG}"

echo "== Docker Trino + Surreal + seed =="
"${BUZZ_ROOT}/scripts/ensure-scenario-data-stack.sh"

echo "== zep-shim (:8100) =="
lsof -i :8100 -sTCP:LISTEN -t 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
cd "${EXPERIMENTS_ROOT}/zep-shim"
nohup env ZEP_SHIM_PORT=8100 arch -arm64 ./.venv/bin/python run.py \
  >>"${EXPERIMENTS_ROOT}/.local/zep-shim.log" 2>&1 &
for i in $(seq 1 45); do
  curl -sf http://127.0.0.1:8100/healthz >/dev/null && break
  sleep 1
done
curl -sf http://127.0.0.1:8100/healthz >/dev/null || {
  echo "zep-shim failed; see ${EXPERIMENTS_ROOT}/.local/zep-shim.log"
  exit 1
}
echo "zep-shim ok"

echo "== MiroFish backend (:5001) =="
lsof -i :5001 -sTCP:LISTEN -t 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
cd "${EXPERIMENTS_ROOT}/MiroFish/backend"
nohup env ZEP_SHIM_BASE_URL="$ZEP_SHIM_BASE_URL" arch -arm64 .venv/bin/python run.py \
  >>"${EXPERIMENTS_ROOT}/.local/mirofish-backend.log" 2>&1 &
for i in $(seq 1 45); do
  curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null && break
  sleep 1
done
curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null || {
  echo "MiroFish failed; see ${EXPERIMENTS_ROOT}/.local/mirofish-backend.log"
  exit 1
}
echo "MiroFish ok"

echo "== seed graph_mcp_eval_fixture =="
python3 "${BUZZ_ROOT}/scripts/seed-mirofish-graph-fixture.py" || true

if curl -sf "${MIROFISH_BASE_URL}/api/graph/data/graph_mcp_eval_fixture" | rg -q '"nodes"'; then
  echo "graph_mcp_eval_fixture ok"
else
  echo "WARN: graph_mcp_eval_fixture empty or missing — check zep-shim logs"
fi

cat <<EOF

Stack ready for Buzz Scenarios:
  TRINO_HOST=${TRINO_HOST}
  SURREALDB_URL=${SURREALDB_URL}
  MIROFISH_BASE_URL=${MIROFISH_BASE_URL}
  Surreal DB: ${SCENARIO_SURREAL_NS}/${BUZZ_SCENARIO_SURREAL_DB}

Buzz Desktop (restart to pick up env if already running):
  export MIROFISH_BASE_URL SURREALDB_URL TRINO_HOST SCENARIO_SURREAL_NS BUZZ_SCENARIO_SURREAL_DB
  cd ${BUZZ_ROOT} && ./scripts/run-buzz-desktop.sh

UI: Sidebar → Scenarios  or  #/scenarios?graphId=graph_mcp_eval_fixture

This tab will print health every 60s (Ctrl+C stops monitoring only).
EOF

while true; do
  sleep 60
  trino_ok=down surreal_ok=down mf_ok=down zep_ok=down
  curl -sf "${TRINO_HOST}/v1/info" >/dev/null && trino_ok=ok
  curl -sf "${SURREALDB_URL}/health" >/dev/null && surreal_ok=ok
  curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null && mf_ok=ok
  curl -sf http://127.0.0.1:8100/healthz >/dev/null && zep_ok=ok
  echo "[$(date -Iseconds)] trino=${trino_ok} surreal=${surreal_ok} mirofish=${mf_ok} zep=${zep_ok}"
done
