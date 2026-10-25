#!/usr/bin/env bash
# 5m agent + relay health loop for local Buzz dev stack.
#
# Rules:
#   - Never auto-restart Buzz desktop
#   - Restart Baseten shim + Fizz/Honey/Pollen harnesses when DOWN (stack awake only)
#   - Health pings use STACK_MONITOR_PING=1 (do not reset idle timer)
#   - Skip recovery when stack state is sleeping
#
# Usage:
#   ./scripts/run-agent-health-loop.sh start [--interval 5m]
#   ./scripts/run-agent-health-loop.sh stop
#   ./scripts/run-agent-health-loop.sh status
#   ./scripts/run-agent-health-loop.sh tick [--ping]
#   ./scripts/run-agent-health-loop.sh test [--ticks 2] [--interval 15s]

set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="${BUZZ_ROOT}/.local/agent-health-loop.pid"
LOG="${BUZZ_ROOT}/.local/agent-health-loop.log"
SENTINEL="AGENT_LOOP_TICK_agent-relay-health"
DEFAULT_INTERVAL="${HEALTH_LOOP_INTERVAL:-300}"

# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/lib/stack-activity.sh"
# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/lib/source-env-safe.sh"
source_env_file "${BUZZ_ROOT}/.env"

parse_interval() {
  local raw="${1:-300}"
  case "$raw" in
    *s|*S) echo "${raw%s}" | tr -d ' ' ;;
    *m|*M) echo "$(("${raw%m}" | tr -d ' ') * 60)" ;;
    *h|*H) echo "$(("${raw%h}" | tr -d ' ') * 3600)" ;;
    *d|*D) echo "$(("${raw%d}" | tr -d ' ') * 86400)" ;;
    *) echo "$raw" ;;
  esac
}

log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG"
}

shim_up() {
  curl -sf http://127.0.0.1:8765/v1/models >/dev/null 2>&1
}

harness_up() {
  local pk pid_file pid
  pk="$1"
  pid_file="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents/agent-pids/${pk}.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  return 1
}

recover_local_workers() {
  local state recovered=0
  state="$(stack_state_get)"
  if [[ "$state" == "sleeping" ]]; then
    log "stack sleeping — skip shim/harness recovery"
    return 0
  fi

  if ! shim_up; then
    log "recover: starting Baseten shim"
    "${BUZZ_ROOT}/scripts/ensure-baseten-shim.sh" >>"$LOG" 2>&1 || true
    recovered=1
  fi

  local need_harness=0
  for pk in \
    2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f \
    fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f \
    b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322; do
    harness_up "$pk" || need_harness=1
  done

  if [[ "$need_harness" -eq 1 ]]; then
    log "recover: starting welcome-team harnesses"
    "${BUZZ_ROOT}/scripts/start-welcome-team-harnesses.sh" >>"$LOG" 2>&1 || true
    recovered=1
  fi

  if [[ "$recovered" -eq 1 ]]; then
    sleep 5
  fi
}

health_loop_tick() {
  local do_ping="${1:-1}"
  mkdir -p "${BUZZ_ROOT}/.local"
  log "=== health tick (ping=${do_ping}) stack=$(stack_state_get) ==="

  recover_local_workers

  local args=(--json)
  [[ "$do_ping" -eq 1 ]] && args+=(--ping)

  set +e
  local out rc
  export HEALTH_LOOP_TICK=1
  out="$("${BUZZ_ROOT}/scripts/test-agents-and-relay.sh" "${args[@]}" 2>&1)"
  rc=$?
  unset HEALTH_LOOP_TICK
  set -e
  printf '%s\n' "$out" >>"$LOG"
  log "tick result: exit=${rc}"
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
      echo "Health loop already running (pid $old_pid)" >&2
      exit 1
    fi
  fi

  mkdir -p "${BUZZ_ROOT}/.local"
  log "starting health loop interval=${interval_sec}s"

  # Run first tick immediately (skill: avoid cold start on first server tick).
  health_loop_tick 1 || true

  (
    while true; do
      sleep "$interval_sec"
      health_loop_tick 1 || true
      echo "${SENTINEL} {\"prompt\":\"Run buzz agent health loop tick: recover shim/harnesses if down (not desktop), then test-agents-and-relay.sh --ping\",\"log\":\"${LOG}\"}"
    done
  ) >>"$LOG" 2>&1 &

  echo $! >"$PID_FILE"
  echo "Health loop started pid=$(cat "$PID_FILE") interval=${interval_sec}s log=${LOG}"
  echo "First tick ran immediately; next sentinel after ${interval_sec}s sleep."
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "Health loop not running (no pid file)"
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    log "stopped health loop pid $pid"
    echo "Health loop stopped (pid $pid)"
  else
    echo "Health loop pid $pid not running"
  fi
  rm -f "$PID_FILE"
}

cmd_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Health loop: RUNNING pid=$(cat "$PID_FILE") log=${LOG}"
  else
    echo "Health loop: STOPPED"
  fi
  echo "Stack state: $(stack_state_get)"
  tail -5 "$LOG" 2>/dev/null | sed 's/^/  /' || true
}

cmd_tick() {
  local do_ping=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-ping) do_ping=0 ;;
      --ping) do_ping=1 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
  done
  health_loop_tick "$do_ping"
}

cmd_test() {
  local ticks=2 interval_sec=15
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ticks) ticks="$2"; shift 2 ;;
      --interval) interval_sec="$(parse_interval "$2")"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  mkdir -p "${BUZZ_ROOT}/.local"
  log "test mode: ${ticks} ticks every ${interval_sec}s"
  local i
  for i in $(seq 1 "$ticks"); do
    health_loop_tick 0 || true
    echo "${SENTINEL} {\"tick\":${i},\"ticks\":${ticks},\"test\":true}"
    [[ "$i" -lt "$ticks" ]] && sleep "$interval_sec"
  done
  echo "AGENT_LOOP_DONE_agent-relay-health {\"ticks\":${ticks},\"log\":\"${LOG}\"}"
}

usage() {
  cat <<'EOF'
Usage: run-agent-health-loop.sh <command> [options]

Commands:
  start [--interval 5m]   Background loop (default 300s); first tick runs immediately
  stop                    Stop background loop
  status                  Show loop + stack state
  tick [--ping|--no-ping] Single health cycle
  test [--ticks N] [--interval 15s]  Foreground test run (no daemon)

Env:
  HEALTH_LOOP_INTERVAL    Seconds between ticks (default 300)
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    start) cmd_start "$@" ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    tick) cmd_tick "$@" ;;
    test) cmd_test "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
  esac
}

main "$@"
