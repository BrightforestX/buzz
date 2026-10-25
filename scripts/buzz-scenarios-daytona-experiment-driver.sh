#!/usr/bin/env bash
# Phase B: run orchestrated scenario on host (always) and optionally inside a Daytona sandbox.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
PIPELINE_SMOKE="${EXPERIMENTS_ROOT}/06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh"
HOST_RUNNER="${BUZZ_ROOT}/scripts/buzz-scenario-run-host.sh"
CUSTOMER_CONTAINER="${BUZZ_ROOT}/scripts/buzz-customer-scenario-container.sh"

echo "== Phase B: host orchestrated scenario (loopback stack) =="
"${HOST_RUNNER}"

echo "== Phase B: customer scenario fleet (all frameworks + chainlets) =="
bash "${CUSTOMER_CONTAINER}" >/dev/null

echo "== Phase B: Daytona operator preflight =="
if [[ -f "${PIPELINE_SMOKE}" ]]; then
  bash "${PIPELINE_SMOKE}"
else
  echo "WARN: smoke-daytona-operator.sh missing — skip Daytona preflight"
fi

if [[ -z "${DAYTONA_API_KEY:-}" ]] || [[ -z "${DAYTONA_ORGANIZATION_ID:-}" ]]; then
  echo "== Phase B: Daytona live sandbox skipped (set DAYTONA_API_KEY + DAYTONA_ORGANIZATION_ID) =="
  echo "Host run above is the authoritative live path for local buzz-stack."
  exit 0
fi

echo "== Phase B: Daytona sandbox exec (orchestrated scenario against host gateway) =="
SANDBOX_ID=""
cleanup() {
  if [[ -n "${SANDBOX_ID}" ]]; then
    daytona delete "${SANDBOX_ID}" --yes 2>/dev/null || true
  fi
}
trap cleanup EXIT

SANDBOX_ID="$(daytona create --name "buzz-scenario-$(date +%s)" --network-allow-list "${BUZZ_SCENARIO_HOST_GATEWAY}" 2>/dev/null | rg -o '[a-f0-9-]{36}' | head -1 || true)"
if [[ -z "${SANDBOX_ID}" ]]; then
  echo "WARN: daytona create did not return a sandbox id — host run already validated"
  exit 0
fi

REMOTE_CMD=$(
  cat <<EOF
set -e
pip install -q httpx 2>/dev/null || python3 -m pip install -q httpx
export MIROFISH_BASE_URL=http://${BUZZ_SCENARIO_HOST_GATEWAY}:5001
export SURREALDB_URL=http://${BUZZ_SCENARIO_HOST_GATEWAY}:8001
export ZEP_SHIM_BASE_URL=http://${BUZZ_SCENARIO_HOST_GATEWAY}:8100/api/v2
export MIROFISH_EXPERIMENT_DB=mirofish_experiments_v2
export SCENARIO_SURREAL_NS=sim
python3 - <<'PY'
import json, os, sys
import httpx
base = os.environ["MIROFISH_BASE_URL"].rstrip("/")
r = httpx.get(f"{base}/health", timeout=20.0)
r.raise_for_status()
print(json.dumps({"daytona_health": r.json(), "mirofish_base_url": base}))
PY
EOF
)

daytona exec "${SANDBOX_ID}" -- bash -lc "${REMOTE_CMD}"
echo "== Phase B: Daytona sandbox reached host MiroFish health =="
