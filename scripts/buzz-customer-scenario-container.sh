#!/usr/bin/env bash
# Customer scenario container: all frameworks + chainlets (host + optional Daytona).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
CHAIN_MCP="${EXPERIMENTS_ROOT}/baseten-chain-mcp"
FLEET_PY="${CHAIN_MCP}/scripts/buzz-customer-daytona-scenario-fleet.py"
REPORT="${BUZZ_ROOT}/.local/buzz-customer-scenario-fleet-report.json"

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export ZEP_SHIM_BASE_URL="${ZEP_SHIM_BASE_URL:-http://127.0.0.1:8100/api/v2}"
export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export BUZZ_ROOT="${BUZZ_ROOT}"
export BUZZ_SCENARIO_HOST_GATEWAY="${BUZZ_SCENARIO_HOST_GATEWAY:-host.docker.internal}"

curl -sf "${SURREALDB_URL}/health" >/dev/null || {
  echo "FAIL: SurrealDB required at ${SURREALDB_URL}" >&2
  exit 1
}

echo "== Customer scenario fleet (host container) ==" >&2
export BUZZ_DAYTONA_FLEET=host
(cd "${CHAIN_MCP}" && uv run python "${FLEET_PY}") >&2 || exit 1

if [[ -n "${DAYTONA_API_KEY:-}" ]] && [[ -n "${DAYTONA_ORGANIZATION_ID:-}" ]]; then
  echo "== Customer scenario fleet (Daytona sandbox smoke) ==" >&2
  SANDBOX_ID=""
  cleanup() {
    [[ -n "${SANDBOX_ID}" ]] && daytona delete "${SANDBOX_ID}" --yes 2>/dev/null || true
  }
  trap cleanup EXIT
  SANDBOX_ID="$(daytona create --name "buzz-customer-$(date +%s)" --network-allow-list "${BUZZ_SCENARIO_HOST_GATEWAY}" 2>/dev/null | rg -o '[a-f0-9-]{36}' | head -1 || true)"
  if [[ -n "${SANDBOX_ID}" ]]; then
    daytona exec "${SANDBOX_ID}" -- bash -lc "curl -sf http://${BUZZ_SCENARIO_HOST_GATEWAY}:8001/health && curl -sf http://${BUZZ_SCENARIO_HOST_GATEWAY}:5001/health" >&2
    export BUZZ_DAYTONA_FLEET=daytona_reachable
  fi
else
  echo "== Daytona fleet skipped (no DAYTONA_API_KEY) — host fleet is authoritative ==" >&2
fi

if [[ -f "${REPORT}" ]]; then
  echo "== Report: ${REPORT} ==" >&2
  python3 - <<PY >&2
import json
from pathlib import Path
p = Path("${REPORT}")
data = json.loads(p.read_text())
fleet = data.get("fleet", {})
print(f"passed={fleet.get('passed')} failed={fleet.get('failed')} catalog={fleet.get('catalog_size')}")
for row in fleet.get("scenarios", []):
    mark = "OK" if row.get("ok") else "FAIL"
    print(f"  [{mark}] {row.get('scenario_key')} engine={row.get('engine')} graph={row.get('graph_id', row.get('graph_snapshot', {}).get('graph_id'))}")
PY
fi

# Tauri parses stdout as JSON (single object).
python3 - <<PY
import json
from pathlib import Path
report = Path("${REPORT}")
if not report.is_file():
    raise SystemExit("missing fleet report")
data = json.loads(report.read_text())
out = {"report_path": str(report), **data.get("fleet", {})}
print(json.dumps(out))
PY
