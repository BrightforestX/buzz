#!/usr/bin/env bash
# Formal proof bundle for Buzz Scenarios: midspiral Quint/P, upstream formal/run.sh, live stack.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
MIDSPIRAL_FLEET="${EXPERIMENTS_ROOT}/03-libraries/midspiral-mcp/python/repos/henri-lemmascript-surreal/formal/verifier-fleet"
UPSTREAM_FORMAL="${EXPERIMENTS_ROOT}/06-pipelines/formal/run.sh"
EVIDENCE="${BUZZ_ROOT}/.local/buzz-scenarios-formal-validate.log"
DESKTOP_URL="${BUZZ_DESKTOP_URL:-http://127.0.0.1:37333/}"

mkdir -p "${BUZZ_ROOT}/.local"
: >"${EVIDENCE}"

log() {
  echo "$@" | tee -a "${EVIDENCE}"
}

run_quint_midspiral() {
  log "== midspiral VerifierFleet (Quint) =="
  if ! command -v quint >/dev/null 2>&1; then
    log "FAIL: quint not on PATH"
    return 1
  fi
  (
    cd "${MIDSPIRAL_FLEET}/quint"
    quint typecheck VerifierFleet.qnt | tee -a "${EVIDENCE}"
    quint test VerifierFleet.qnt | tee -a "${EVIDENCE}"
  )
  log "  ok VerifierFleet.qnt"
  local qiskit_qnt="${EXPERIMENTS_ROOT}/baseten-chain-mcp/formal/quint/ScenarioQiskitSandbox.qnt"
  if [[ -f "${qiskit_qnt}" ]]; then
    log "== baseten-chain-mcp ScenarioQiskitSandbox (Quint) =="
    (
      cd "$(dirname "${qiskit_qnt}")"
      quint typecheck ScenarioQiskitSandbox.qnt | tee -a "${EVIDENCE}"
      quint test ScenarioQiskitSandbox.qnt | tee -a "${EVIDENCE}"
    )
    log "  ok ScenarioQiskitSandbox.qnt"
  fi
}

run_p_midspiral() {
  log "== midspiral Orchestrator (P modeling) =="
  if ! command -v p >/dev/null 2>&1; then
    log "FAIL: P checker (p) not on PATH"
    return 1
  fi
  (
    cd "${MIDSPIRAL_FLEET}/p"
    p compile --pproj orchestrator.pproj | tee -a "${EVIDENCE}"
  )
  local dll
  dll="$(
    find "${MIDSPIRAL_FLEET}/p/out" \
      -path '*/net8.0/orchestrator.dll' ! -path '*/ref/*' ! -path '*/obj/*' 2>/dev/null | head -1
  )"
  if [[ -z "${dll}" ]]; then
    log "FAIL: orchestrator.dll not found after p compile"
    return 1
  fi
  p check "${dll}" --testcase TurnOk --schedules 100 --max-steps 200 | tee -a "${EVIDENCE}"
  p check "${dll}" --testcase TurnBlockingGate --schedules 100 --max-steps 200 | tee -a "${EVIDENCE}"
  log "  ok Orchestrator P testcases"
}

run_upstream_formal() {
  log "== upstream Quint + P pipeline (formal/run.sh) =="
  if [[ ! -f "${UPSTREAM_FORMAL}" ]]; then
    log "FAIL: missing ${UPSTREAM_FORMAL}"
    return 1
  fi
  bash "${UPSTREAM_FORMAL}" | tee -a "${EVIDENCE}"
  log "  ok formal/run.sh"
}

run_buzz_scenarios_live() {
  log "== Buzz Scenarios live + automated gates =="
  "${BUZZ_ROOT}/scripts/buzz-scenarios-automated-red-green.sh" | tee -a "${EVIDENCE}"
  log "  ok buzz-scenarios-automated-red-green"
}

probe_buzz_desktop() {
  log "== Buzz Desktop UI (${DESKTOP_URL}) =="
  local code
  code="$(curl -sf -o /dev/null -w '%{http_code}' "${DESKTOP_URL}" 2>/dev/null || echo 000)"
  if [[ "${code}" == "200" ]]; then
    log "  ok Buzz Desktop HTTP ${code}"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      open "${DESKTOP_URL}#/scenarios" 2>/dev/null || true
    fi
    return 0
  fi
  log "  WARN: Buzz Desktop not reachable (HTTP ${code}) — start: ${BUZZ_ROOT}/scripts/run-buzz-desktop.sh"
  return 0
}

main() {
  log "buzz-scenarios-formal-validate started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run_quint_midspiral
  run_p_midspiral
  run_upstream_formal
  run_buzz_scenarios_live
  probe_buzz_desktop
  log "== buzz-scenarios-formal-validate: PASS =="
}

main "$@"
