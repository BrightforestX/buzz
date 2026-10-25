#!/usr/bin/env bash
# Four Terminal windows: data (Docker Trino+Surreal), zep-shim, MiroFish, health watch (host Python).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
CHAIN_COMPOSE="${EXPERIMENTS_ROOT}/baseten-chain-mcp/docker-compose.local.yml"
SEED="${BUZZ_ROOT}/scripts/ensure-scenario-data-stack.sh"

if [[ -f "${BUZZ_ROOT}/bin/activate-hermit" ]]; then
  # shellcheck disable=SC1091
  . "${BUZZ_ROOT}/bin/activate-hermit"
fi

open_terminal() {
  local title="$1"
  local inner_cmd="$2"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Pane [${title}]: ${inner_cmd}"
    return 0
  fi
  local escaped="${inner_cmd//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  osascript \
    -e "tell application \"Terminal\" to activate" \
    -e "tell application \"Terminal\" to do script \"printf '\\\\033]0;${title}\\\\007' && ${escaped}\""
}

open_terminal "buzz-scenarios: trino+surreal" \
  "if docker info >/dev/null 2>&1; then cd $(printf '%q' "$EXPERIMENTS_ROOT/baseten-chain-mcp") && docker compose -f docker-compose.local.yml up trino surrealdb; else echo 'Start Docker Desktop, then re-run: docker compose -f docker-compose.local.yml up trino surrealdb'; exec bash; fi"

open_terminal "buzz-scenarios: zep-shim" \
  "cd $(printf '%q' "$EXPERIMENTS_ROOT/zep-shim") && ZEP_SHIM_PORT=8100 arch -arm64 ./.venv/bin/python run.py"

open_terminal "buzz-scenarios: mirofish" \
  "cd $(printf '%q' "$EXPERIMENTS_ROOT/MiroFish/backend") && ZEP_SHIM_BASE_URL=http://127.0.0.1:8100/api/v2 arch -arm64 .venv/bin/python run.py"

open_terminal "buzz-scenarios: seed+watch" \
  "cd $(printf '%q' "$BUZZ_ROOT") && sleep 20 && $(printf '%q' "$SEED") && while true; do date -Iseconds; curl -sf http://127.0.0.1:8080/v1/info >/dev/null && echo trino=ok || echo trino=down; curl -sf http://127.0.0.1:8001/health >/dev/null && echo surreal=ok || echo surreal=down; curl -sf http://127.0.0.1:8100/healthz >/dev/null && echo zep=ok || echo zep=down; curl -sf http://127.0.0.1:5001/health >/dev/null && echo mirofish=ok || echo mirofish=down; sleep 60; done"

echo "Opened four Terminal windows (host zep/MiroFish + Docker Trino/Surreal)."
echo "Prefer all-in-docker when Docker Desktop is up: ./scripts/open-scenario-stack-panes.sh"
