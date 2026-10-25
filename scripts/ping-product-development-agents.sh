#!/usr/bin/env bash
# Send @mention smoke-test pings to Welcome Team agents in #product-development
# as the human operator (via relay-env identity). Verifies harness + LLM shim.
#
# Usage:
#   ./scripts/ping-product-development-agents.sh           # ping Fizz, Honey, Pollen
#   ./scripts/ping-product-development-agents.sh --wait    # ping then tail logs for turn delivered
#   ./scripts/ping-product-development-agents.sh --agent fizz
#
# Prereqs: ./scripts/run-buzz-dev.sh (or ensure-baseten-shim + start-welcome-team-harnesses)

set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANNEL_ID="${BUZZ_PRODUCT_DEV_CHANNEL:-28c8bf26-10fa-42e7-b658-38092562bfe1}"
BUZZ="${BUZZ_BIN:-${BUZZ_ROOT}/target/debug/buzz}"
WAIT_LOGS=0
AGENT_FILTER="all"
LOG_DIR="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents/logs"

FIZZ_PK="2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f"
HONEY_PK="fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f"
POLLEN_PK="b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322"

usage() {
  cat <<'EOF'
Usage: ./scripts/ping-product-development-agents.sh [--wait] [--agent fizz|honey|pollen|all]

  Sends operator @mention pings to Welcome Team agents in #product-development.
  Requires Baseten shim (:8765) and buzz-acp harnesses to be running.

Options:
  --wait       After pings, wait ~45s and grep agent logs for "turn delivered"
  --agent NAME Ping one agent only (default: all three)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) WAIT_LOGS=1 ;;
    --agent)
      shift
      AGENT_FILTER="${1:-all}"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/relay-env.sh"

if ! curl -sf http://127.0.0.1:8765/v1/models >/dev/null 2>&1; then
  echo "ERROR: Baseten LLM shim not reachable on :8765. Run: ./scripts/ensure-baseten-shim.sh" >&2
  exit 1
fi

if [[ ! -x "$BUZZ" ]]; then
  echo "ERROR: buzz binary not found at $BUZZ (cargo build -p buzz-cli)" >&2
  exit 1
fi

_stamp() { date -u +%H:%M:%S; }

_ping() {
  local name="$1" pk="$2" prompt="$3"
  local prefix=""
  if [[ "${STACK_MONITOR_PING:-0}" == "1" ]]; then
    prefix="[healthcheck] "
  fi
  local content="${prefix}@${name} agent ping $(_stamp) — ${prompt}"
  echo "→ @${name} …"
  "$BUZZ" messages send \
    --channel "$CHANNEL_ID" \
    --content "$content" \
    --mention "$pk"
  if [[ "${STACK_MONITOR_PING:-0}" != "1" ]]; then
    # shellcheck source=/dev/null
    source "${BUZZ_ROOT}/scripts/lib/stack-activity.sh"
    stack_activity_record "relay_post"
  fi
  sleep 2
}

should_ping() {
  local name_lower
  name_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$AGENT_FILTER" == "all" || "$AGENT_FILTER" == "$name_lower" ]]
}

echo "Channel: #product-development ($CHANNEL_ID)"
echo "Identity: operator (relay-env)"
echo ""

if should_ping Fizz; then
  _ping Fizz "$FIZZ_PK" "reply with one sentence confirming you are online."
fi
if should_ping Honey; then
  _ping Honey "$HONEY_PK" "reply with one warm sentence confirming you are online."
fi
if should_ping Pollen; then
  _ping Pollen "$POLLEN_PK" "reply with one curious sentence confirming you are online."
fi

echo ""
echo "Pings sent. Check #product-development in Buzz desktop for agent replies."

if [[ "$WAIT_LOGS" -eq 1 ]]; then
  echo "Waiting 45s for harness turns …"
  sleep 45
  for entry in \
    "${FIZZ_PK}:Fizz" \
    "${HONEY_PK}:Honey" \
    "${POLLEN_PK}:Pollen"; do
    IFS=: read -r pk name <<<"$entry"
    if ! should_ping "$name"; then
      continue
    fi
    log="$(find "$LOG_DIR" -maxdepth 1 -name "${pk}__*.log" 2>/dev/null | head -1)"
    if [[ -z "$log" ]]; then
      echo "  ${name}: no log file"
      continue
    fi
    if tail -20 "$log" | grep -q "turn delivered"; then
      last="$(tail -20 "$log" | grep "turn delivered" | tail -1)"
      echo "  ${name}: OK — ${last##*: }"
      if [[ "${STACK_MONITOR_PING:-0}" != "1" ]]; then
        # shellcheck source=/dev/null
        source "${BUZZ_ROOT}/scripts/lib/stack-activity.sh"
        stack_activity_record "agent_turn"
      fi
    else
      echo "  ${name}: NO turn delivered in last 20 log lines — check $log"
    fi
  done
fi
