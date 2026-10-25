#!/usr/bin/env bash
# One-shot local dev stack: Baseten shim → welcome-team harnesses → Buzz desktop.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="start"

usage() {
  cat <<'EOF'
Usage: ./scripts/run-buzz-dev.sh [--stop | --stop-all | --status]

  (default)  Start LLM shim, Fizz/Honey/Pollen harnesses, and desktop
  --stop     Stop desktop only (harnesses/shim keep running)
  --stop-all Stop desktop, harnesses, and Baseten shim
  --status   Show shim, harness, and desktop health
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION="stop" ;;
    --stop-all) ACTION="stop-all" ;;
    --status) ACTION="status" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

case "$ACTION" in
  start)
    # shellcheck source=/dev/null
    source "${BUZZ_ROOT}/scripts/lib/stack-activity.sh"
    stack_activity_record "desktop"
    "${BUZZ_ROOT}/scripts/ensure-baseten-shim.sh"
    "${BUZZ_ROOT}/scripts/start-welcome-team-harnesses.sh"
    "${BUZZ_ROOT}/scripts/run-buzz-desktop.sh"
    ;;
  stop)
    "${BUZZ_ROOT}/scripts/run-buzz-desktop.sh" --stop
    ;;
  stop-all)
    "${BUZZ_ROOT}/scripts/run-buzz-desktop.sh" --stop || true
    "${BUZZ_ROOT}/scripts/stop-welcome-team-harnesses.sh" || true
    "${BUZZ_ROOT}/scripts/ensure-baseten-shim.sh" --stop || true
    ;;
  status)
    echo "=== Baseten shim (:8765) ==="
    if curl -sf http://127.0.0.1:8765/v1/models >/dev/null 2>&1; then
      echo "  OK"
    else
      echo "  DOWN — run: ./scripts/ensure-baseten-shim.sh"
    fi
    echo "=== Welcome team harnesses ==="
    for pk in \
      2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f:Fizz \
      fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f:Honey \
      b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322:Pollen; do
      IFS=: read -r pubkey name <<<"$pk"
      pid_file="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents/agent-pids/${pubkey}.pid"
      pid=""
      if [[ -f "$pid_file" ]]; then
        pid="$(cat "$pid_file" 2>/dev/null || true)"
      fi
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "  ${name}: OK (pid ${pid})"
        continue
      fi
      # Harness may predate pid files — match running buzz-acp by agent name in system prompt.
      found="$(pgrep -f "buzz-acp.*You are ${name}," 2>/dev/null | head -1 || true)"
      if [[ -n "$found" ]]; then
        echo "  ${name}: OK (pid ${found}, no pid file)"
      else
        echo "  ${name}: DOWN — run: ./scripts/start-welcome-team-harnesses.sh"
      fi
    done
    echo "=== Desktop ==="
    "${BUZZ_ROOT}/scripts/run-buzz-desktop.sh" --status
    ;;
esac
