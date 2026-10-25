#!/usr/bin/env bash
# 10m green/red loop for Buzz Scenarios + Workflows (local agent wake via sentinel).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="${BUZZ_ROOT}/.local/scenarios-workflows-green-red-loop.pid"
LOG="${BUZZ_ROOT}/.local/scenarios-workflows-green-red-loop.log"
SENTINEL="AGENT_LOOP_TICK_scenarios-workflows-green-red"
DEFAULT_INTERVAL="${SCENARIOS_WORKFLOWS_LOOP_INTERVAL:-600}"
PROBE="${BUZZ_ROOT}/scripts/buzz-scenarios-workflows-green-red.sh"

parse_interval() {
  local raw="${1:-600}"
  case "$raw" in
    *s|*S) echo "${raw%s}" | tr -d ' ' ;;
    *m|*M) local n="${raw%m}"; n="${n// /}"; echo $((n * 60)) ;;
    *h|*H) local h="${raw%h}"; h="${h// /}"; echo $((h * 3600)) ;;
    *) echo "$raw" ;;
  esac
}

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG"
}

loop_tick() {
  log "running ${PROBE}"
  set +e
  "$PROBE"
  local rc=$?
  set -e
  log "probe exit=${rc}"
  return "$rc"
}

cmd_start() {
  local interval_sec="$DEFAULT_INTERVAL"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval)
        interval_sec="$(parse_interval "$2")"
        shift 2
        ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -f "$PID_FILE" ]]; then
    local old_pid
    old_pid="$(cat "$PID_FILE")"
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "Loop already running (pid $old_pid)" >&2
      exit 1
    fi
  fi

  mkdir -p "${BUZZ_ROOT}/.local"
  chmod +x "$PROBE" 2>/dev/null || true
  log "starting interval=${interval_sec}s"

  loop_tick || true

  (
    while true; do
      sleep "$interval_sec"
      loop_tick || true
      echo "${SENTINEL} {\"prompt\":\"Red and green team Buzz Scenarios and Workflows: run ${PROBE}, fix green failures, log red warnings in specs/007-buzz-green-red-team/README.md run log.\",\"log\":\"${LOG}\"}" | tee -a "$LOG"
    done
  ) &

  echo $! >"$PID_FILE"
  echo "Scenarios/workflows green-red loop started pid=$(cat "$PID_FILE") interval=${interval_sec}s log=${LOG}"
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "Loop not running"
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    log "stopped pid $pid"
  fi
  rm -f "$PID_FILE"
  echo "Loop stopped"
}

cmd_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "RUNNING pid=$(cat "$PID_FILE") log=${LOG}"
  else
    echo "STOPPED"
  fi
  tail -8 "$LOG" 2>/dev/null | sed 's/^/  /' || true
}

usage() {
  cat <<'EOF'
Usage: run-scenarios-workflows-green-red-loop.sh <start|stop|status|tick> [--interval 10m]

Env: SCENARIOS_WORKFLOWS_LOOP_INTERVAL (seconds, default 600)
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    start) cmd_start "$@" ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    tick) loop_tick ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown: $cmd" >&2; usage >&2; exit 1 ;;
  esac
}

main "$@"
