#!/usr/bin/env bash
# Green / red probes for Buzz Desktop Scenarios + Workflows features.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESKTOP="${BUZZ_ROOT}/desktop"
LOG_DIR="${BUZZ_ROOT}/.local"
LOG="${LOG_DIR}/scenarios-workflows-green-red.log"
TS="$(date -Iseconds)"

mkdir -p "$LOG_DIR"
exec 3>>"$LOG"
echo "===== tick ${TS} =====" >&3

GREEN_FAIL=0
RED_WARN=0

log() { echo "$*" | tee -a "$LOG" >&3; }
warn() { RED_WARN=$((RED_WARN + 1)); log "RED-WARN: $*"; }
fail() { GREEN_FAIL=$((GREEN_FAIL + 1)); log "GREEN-FAIL: $*"; }

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
export BUZZ_SCENARIO_SURREAL_DB="${BUZZ_SCENARIO_SURREAL_DB:-buzz_mirofish_scenario}"
export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"
CHAIN_MCP_ROOT="$(cd "${BUZZ_ROOT}/../../baseten-chain-mcp" 2>/dev/null && pwd || true)"

log "== GREEN: route tree includes /scenarios =="
if rg -q 'scenariosRouteImport' "${DESKTOP}/src/app/routeTree.gen.ts" 2>/dev/null; then
  log "  ok routeTree.gen.ts"
else
  log "  regenerating route tree..."
  if (cd "$DESKTOP" && node ./scripts/generate-route-tree.mjs >>"$LOG" 2>&1); then
    log "  ok routes:gen"
  else
    fail "route tree missing /scenarios and routes:gen failed"
  fi
fi

log "== GREEN: scenarios unit tests =="
if (cd "$DESKTOP" && node --import ./test-loader.mjs --experimental-strip-types --test \
  "src/features/scenarios/**/*.test.mjs" >>"$LOG" 2>&1); then
  log "  ok scenarios tests"
else
  fail "scenarios unit tests failed"
fi

log "== GREEN: workflows unit tests =="
if (cd "$DESKTOP" && node --import ./test-loader.mjs --experimental-strip-types --test \
  "src/features/workflows/**/*.test.mjs" >>"$LOG" 2>&1); then
  log "  ok workflows tests"
else
  fail "workflows unit tests failed"
fi

log "== GREEN: buzz-desktop compile (scenario Tauri commands) =="
if (cd "$DESKTOP/src-tauri" && cargo check -p buzz-desktop >>"$LOG" 2>&1); then
  log "  ok cargo check"
else
  fail "cargo check -p buzz-desktop failed"
fi

log "== GREEN: Trino + Surreal stack probes =="
if curl -sf "${TRINO_HOST}/v1/info" >/dev/null; then
  log "  ok Trino ${TRINO_HOST}"
else
  fail "Trino not reachable at ${TRINO_HOST}"
fi
if curl -sf "${SURREALDB_URL}/health" >/dev/null; then
  log "  ok Surreal ${SURREALDB_URL}"
else
  fail "Surreal not reachable at ${SURREALDB_URL}"
fi
if curl -sf -X POST "${SURREALDB_URL}/sql" -u 'root:root' \
  -H 'Accept: application/json' \
  -H "surreal-ns: ${SCENARIO_SURREAL_NS}" \
  -H "surreal-db: ${BUZZ_SCENARIO_SURREAL_DB}" \
  --data 'SELECT count() FROM pm_issue GROUP ALL;' | rg -q '"status":"OK"'; then
  log "  ok Surreal pm_issue query (${SCENARIO_SURREAL_NS}/${BUZZ_SCENARIO_SURREAL_DB})"
else
  warn "Surreal pm_issue empty or query failed (run ensure-scenario-data-stack.sh)"
fi

log "== GREEN: baseten-chain-mcp scenario pytest =="
if [[ -n "${CHAIN_MCP_ROOT:-}" ]] && [[ -d "${CHAIN_MCP_ROOT}" ]]; then
  if (cd "${CHAIN_MCP_ROOT}" && uv run pytest tests/scenario/ -q >>"$LOG" 2>&1); then
    log "  ok baseten-chain-mcp tests/scenario"
  else
    fail "baseten-chain-mcp scenario pytest failed"
  fi
else
  warn "baseten-chain-mcp root not found — skip scenario pytest"
fi

log "== GREEN: Scenarios feature wiring (static) =="
if rg -q 'run_scenario_mirofish_experiment_fixture' "${DESKTOP}/src-tauri/src/lib.rs"; then
  log "  ok run_scenario_mirofish_experiment_fixture registered"
else
  fail "run_scenario_mirofish_experiment_fixture not in lib.rs"
fi
if rg -q 'fetch_graph_from_surreal_snapshot' "${DESKTOP}/src-tauri/src/commands/mirofish_scenario.rs"; then
  log "  ok Surreal graph_snapshot fallback in Tauri"
else
  fail "missing fetch_graph_from_surreal_snapshot"
fi
if [[ -f "${BUZZ_ROOT}/scripts/buzz-scenario-run-host.sh" ]]; then
  log "  ok buzz-scenario-run-host.sh"
else
  fail "missing buzz-scenario-run-host.sh"
fi
if [[ -f "${BUZZ_ROOT}/scripts/buzz-customer-scenario-container.sh" ]]; then
  log "  ok buzz-customer-scenario-container.sh"
else
  fail "missing buzz-customer-scenario-container.sh"
fi
if rg -q 'qiskit_scenario_simulation_seed_tool' "${EXPERIMENTS_ROOT}/baseten-chain-mcp/src/baseten_chain_mcp/mcp_server.py"; then
  log "  ok qiskit sandbox MCP tools registered"
else
  fail "missing qiskit MCP tools in baseten-chain-mcp"
fi

log "== RED: experiment id sanitization (R9) =="
if rg -q 'experimentId contains invalid characters' "${DESKTOP}/src-tauri/src/commands/mirofish_scenario.rs"; then
  log "  ok get_scenario_mirofish_experiment rejects bad ids"
else
  warn "missing experiment id character guard (R9)"
fi

log "== RED: Daytona driver present (Phase B) =="
if [[ -x "${BUZZ_ROOT}/scripts/buzz-scenarios-daytona-experiment-driver.sh" ]]; then
  log "  ok daytona experiment driver script"
else
  warn "buzz-scenarios-daytona-experiment-driver.sh missing or not executable"
fi

log "== GREEN: MiroFish experiment registry (Surreal ${MIROFISH_EXPERIMENT_DB}) =="
if rg -q 'list_scenario_mirofish_experiments' "${DESKTOP}/src-tauri/src/commands/mirofish_scenario.rs"; then
  log "  ok Tauri list_scenario_mirofish_experiments"
else
  fail "missing list_scenario_mirofish_experiments Tauri command"
fi
if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null && [[ -n "${CHAIN_MCP_ROOT:-}" ]] && [[ -d "${CHAIN_MCP_ROOT}" ]]; then
  if "${BUZZ_ROOT}/scripts/buzz-scenario-run-host.sh" >>"$LOG" 2>&1; then
    log "  ok buzz-scenario-run-host.sh (orchestrated live sync + graph snapshot)"
  else
    fail "buzz-scenario-run-host.sh failed (MiroFish + Surreal + zep must be up)"
  fi
fi
if curl -sf -X POST "${SURREALDB_URL}/sql" -u 'root:root' \
  -H 'Accept: application/json' \
  -H "surreal-ns: ${SCENARIO_SURREAL_NS}" \
  -H "surreal-db: ${MIROFISH_EXPERIMENT_DB}" \
  --data "SELECT graph_id, array::len(nodes) AS node_count FROM graph_snapshot WHERE graph_id = 'graph_mcp_eval_fixture' LIMIT 1;" \
  | rg -q '"graph_id"'; then
  log "  ok graph_snapshot for graph_mcp_eval_fixture"
else
  if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null; then
    fail "graph_snapshot missing for graph_mcp_eval_fixture — run buzz-scenario-run-host.sh"
  else
    warn "MiroFish down — skip graph_snapshot probe"
  fi
fi
if curl -sf -X POST "${SURREALDB_URL}/sql" -u 'root:root' \
  -H 'Accept: application/json' \
  -H "surreal-ns: ${SCENARIO_SURREAL_NS}" \
  -H "surreal-db: ${MIROFISH_EXPERIMENT_DB}" \
  --data 'SELECT experiment_id, status, report_id, updated_at FROM mirofish_experiment ORDER BY updated_at DESC LIMIT 1;' \
  | rg -q '"experiment_id"'; then
  log "  ok mirofish_experiment row in ${MIROFISH_EXPERIMENT_DB}"
else
  if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null; then
    fail "mirofish_experiment empty — run baseten-chain-mcp/scripts/buzz-mirofish-experiment-flow.py"
  else
    warn "MiroFish down — skip live experiment sync (UI list needs Surreal + prior seed)"
  fi
fi

log "== GREEN: MiroFish graph API (optional) =="
ZEP_SHIM_BASE_URL="${ZEP_SHIM_BASE_URL:-http://127.0.0.1:8100/api/v2}"
graph_ok=0
if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null; then
  if curl -sf "${MIROFISH_BASE_URL}/api/graph/data/graph_mcp_eval_fixture" | rg -q '"nodes"'; then
    log "  ok graph_mcp_eval_fixture via MiroFish API"
    graph_ok=1
  fi
fi
if [[ "$graph_ok" -eq 0 ]] && curl -sf http://127.0.0.1:8100/healthz >/dev/null; then
  if curl -sf -X POST "${ZEP_SHIM_BASE_URL}/graph/node/graph/graph_mcp_eval_fixture" \
    -H 'Content-Type: application/json' \
    -d '{"limit":1}' | rg -q '"uuid_"' ; then
    log "  ok graph_mcp_eval_fixture via zep-shim (Buzz Scenarios fallback path)"
    graph_ok=1
  fi
fi
if [[ "$graph_ok" -eq 0 ]]; then
  if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null || curl -sf http://127.0.0.1:8100/healthz >/dev/null; then
    warn "graph_mcp_eval_fixture missing — run scripts/seed-mirofish-graph-fixture.py (Ollama + zep-shim)"
  else
    warn "MiroFish/zep down — Scenarios graph canvas will not load"
  fi
fi

log "== RED: Scenarios Tauri loopback guard =="
if rg -q 'loopback_http_only' "${DESKTOP}/src-tauri/src/commands/mirofish_scenario.rs"; then
  log "  ok loopback-only HTTP for graph + Surreal"
else
  warn "missing loopback_http_only in mirofish_scenario.rs"
fi

log "== RED: MiroFish unauthenticated surface (R1) =="
if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null; then
  code="$(curl -s -o /dev/null -w '%{http_code}' "${MIROFISH_BASE_URL}/api/simulation/list")"
  if [[ "$code" == "200" ]]; then
    warn "MiroFish /api/simulation/list returns 200 without auth (expected local risk)"
  else
    log "  note simulation list HTTP ${code}"
  fi
fi

log "== RED: graph API when zep/MiroFish misconfigured (R5) =="
if curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null; then
  if ! curl -sf "http://127.0.0.1:8100/healthz" >/dev/null 2>&1; then
    ent_code="$(curl -s -o /dev/null -w '%{http_code}' \
      "${MIROFISH_BASE_URL}/api/simulation/entities/graph_mcp_eval_fixture")"
    if [[ "$ent_code" =~ ^5 ]]; then
      log "  ok entities API fails (${ent_code}) when zep-shim down"
    else
      warn "entities API HTTP ${ent_code} with zep-shim down (unexpected)"
    fi
  else
    log "  skip R5 (zep-shim healthy)"
  fi
fi

log "== RED: Workflows preview feature gate file =="
if [[ -f "${BUZZ_ROOT}/preview-features.json" ]] && rg -q '"workflows"' "${BUZZ_ROOT}/preview-features.json"; then
  log "  ok workflows feature registered"
else
  warn "workflows missing from preview-features.json"
fi

log "== SUMMARY green_fail=${GREEN_FAIL} red_warn=${RED_WARN} =="
if [[ "$GREEN_FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
