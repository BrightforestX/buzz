#!/usr/bin/env bash
# Live infra + formal proof: Buzz Desktop, data stack, Qiskit sandbox tools, scenario fleet.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
CHAIN_MCP="${EXPERIMENTS_ROOT}/baseten-chain-mcp"
# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/instance-env.sh"
DESKTOP_URL="${BUZZ_DESKTOP_URL:-http://127.0.0.1:${BUZZ_VITE_PORT}/}"
LOG="${BUZZ_ROOT}/.local/buzz-scenarios-live-infra-validate.log"
mkdir -p "${BUZZ_ROOT}/.local"
: >"${LOG}"

log() { echo "$@" | tee -a "${LOG}"; }

wait_desktop() {
  local tries=0
  while [[ "${tries}" -lt 120 ]]; do
    local code
    code="$(curl -sf -o /dev/null -w '%{http_code}' "${DESKTOP_URL}" 2>/dev/null || echo 000)"
    if [[ "${code}" == "200" ]]; then
      log "  ok Buzz Desktop HTTP ${code} at ${DESKTOP_URL}"
      return 0
    fi
    tries=$((tries + 1))
    sleep 2
  done
  log "FAIL: Buzz Desktop not reachable at ${DESKTOP_URL} after 240s"
  return 1
}

ensure_desktop() {
  if curl -sf "${DESKTOP_URL}" >/dev/null 2>&1; then
    log "Buzz Desktop already up at ${DESKTOP_URL}"
    return 0
  fi
  log "Starting Buzz Desktop…"
  "${BUZZ_ROOT}/scripts/run-buzz-desktop.sh" >>"${LOG}" 2>&1 || true
  wait_desktop
}

log "== live infra validate started $(date -u +%Y-%m-%dT%H:%M:%SZ) =="

ensure_desktop || exit 1

log "== scenario data stack (Trino + Surreal + MiroFish deps) =="
BUZZ_STACK_SKIP_DOCKER="${BUZZ_STACK_SKIP_DOCKER:-0}" \
  "${BUZZ_ROOT}/scripts/ensure-scenario-data-stack.sh" >>"${LOG}" 2>&1

log "== Qiskit agent sandbox tools =="
(cd "${CHAIN_MCP}" && uv sync --group qiskit --quiet)
(cd "${CHAIN_MCP}" && uv run pytest tests/scenario/test_qiskit_sandbox.py -q) | tee -a "${LOG}"

log "== Qiskit MCP tool smoke =="
(cd "${CHAIN_MCP}" && uv run python - <<'PY') | tee -a "${LOG}"
from baseten_chain_mcp.scenario.qiskit_sandbox import (
    qiskit_run_circuit,
    qiskit_sandbox_health,
    qiskit_scenario_simulation_seed,
)
print(qiskit_sandbox_health())
print(qiskit_run_circuit("bell", shots=32, seed=7))
print(qiskit_scenario_simulation_seed("mirofish_pm", shots=64))
PY

log "== formal + scenarios (Quint/P/midspiral + fleet) =="
"${BUZZ_ROOT}/scripts/buzz-scenarios-formal-validate.sh" >>"${LOG}" 2>&1

log "== live infra validate: PASS =="
