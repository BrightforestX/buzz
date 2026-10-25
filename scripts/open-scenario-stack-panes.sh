#!/usr/bin/env bash
# Start Buzz Scenarios stack in Docker and open Terminal panes (one service group per window).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS_ROOT="$(cd "${BUZZ_ROOT}/../.." && pwd)"
COMPOSE_FILE="${BUZZ_ROOT}/docker-compose.buzz-stack.yml"
LOG_DIR="${BUZZ_ROOT}/.local"
SEED="${BUZZ_ROOT}/scripts/ensure-scenario-data-stack.sh"

mkdir -p "$LOG_DIR"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running — opening host-process panes instead." >&2
  exec "${BUZZ_ROOT}/scripts/open-scenario-stack-panes-host.sh"
fi

if [[ -f "${BUZZ_ROOT}/bin/activate-hermit" ]]; then
  # shellcheck disable=SC1091
  . "${BUZZ_ROOT}/bin/activate-hermit"
fi

export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"

open_terminal() {
  local title="$1"
  local inner_cmd="$2"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Pane [${title}]: ${inner_cmd}"
    return 0
  fi
  local escaped
  escaped="${inner_cmd//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  osascript \
    -e "tell application \"Terminal\" to activate" \
    -e "tell application \"Terminal\" to do script \"printf '\\\\033]0;${title}\\\\007' && cd $(printf '%q' "$BUZZ_ROOT") && ${escaped}\""
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

echo "== Pull / build (first run may take several minutes) =="
# Free host listeners if a prior herd left processes on these ports
for port in 8080 8001 8100 5001 7687; do
  lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | xargs kill -9 2>/dev/null || true
done
sleep 1

compose pull mirofish 2>/dev/null || true
compose build zep-shim 2>&1 | tail -5

echo "== docker compose up -d =="
compose up -d

echo "== Wait for Trino, Surreal, zep, MiroFish =="
for i in $(seq 1 90); do
  ok=0
  curl -sf "${TRINO_HOST}/v1/info" >/dev/null && ok=$((ok + 1))
  curl -sf "${SURREALDB_URL}/health" >/dev/null && ok=$((ok + 1))
  curl -sf http://127.0.0.1:8100/healthz >/dev/null && ok=$((ok + 1))
  curl -sf "${MIROFISH_BASE_URL}/health" >/dev/null && ok=$((ok + 1))
  if [[ "$ok" -ge 4 ]]; then
    break
  fi
  sleep 2
done

echo "== Seed Trino → Surreal (host uv; containers on localhost ports) =="
"$SEED" 2>&1 | tail -8

echo "== Open log panes =="
open_terminal "buzz-scenarios: data" \
  "docker compose -f $(printf '%q' "$COMPOSE_FILE") logs -f trino surrealdb"

open_terminal "buzz-scenarios: graph memory" \
  "docker compose -f $(printf '%q' "$COMPOSE_FILE") logs -f neo4j zep-shim"

open_terminal "buzz-scenarios: mirofish" \
  "docker compose -f $(printf '%q' "$COMPOSE_FILE") logs -f mirofish"

open_terminal "buzz-scenarios: watch" \
  "while true; do date -Iseconds; curl -sf ${TRINO_HOST}/v1/info >/dev/null && echo trino=ok || echo trino=down; curl -sf ${SURREALDB_URL}/health >/dev/null && echo surreal=ok || echo surreal=down; curl -sf http://127.0.0.1:8100/healthz >/dev/null && echo zep=ok || echo zep=down; curl -sf ${MIROFISH_BASE_URL}/health >/dev/null && echo mirofish=ok || echo mirofish=down; sleep 60; done"

cat <<EOF

Scenarios stack (Docker) is up.
  Compose: ${COMPOSE_FILE}
  Stop:    cd ${BUZZ_ROOT} && docker compose -f docker-compose.buzz-stack.yml down
  Buzz UI: #/scenarios?graphId=graph_mcp_eval_fixture

Restart Buzz Desktop so Tauri sees MIROFISH_BASE_URL / SURREALDB_URL (run-buzz-desktop exports defaults).
EOF
