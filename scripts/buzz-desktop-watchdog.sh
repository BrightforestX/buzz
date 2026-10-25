#!/usr/bin/env bash
# Detached watchdog: restart Buzz desktop if the launcher exits unexpectedly.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${repo_root}/.local"
PID_FILE="${STATE_DIR}/buzz-desktop.pid"
READY_AT_FILE="${STATE_DIR}/buzz-desktop.ready-at"
STOP_FLAG_FILE="${STATE_DIR}/buzz-desktop.stop"
LOG_FILE="${STATE_DIR}/buzz-desktop.log"
WATCHDOG_GRACE_SECS=120
CHECK_INTERVAL=30

log() { printf '[run-buzz-desktop-watchdog] %s %s\n' "$(date -Iseconds)" "$*" >>"$LOG_FILE"; }

vite_port() {
  (
    cd "$repo_root"
    # shellcheck disable=SC1091
    source "${repo_root}/scripts/instance-env.sh"
    echo "$BUZZ_VITE_PORT"
  )
}

vite_url() {
  echo "http://localhost:$(vite_port)/"
}

buzz_desktop_pids() {
  local pid
  pid="$(pgrep -x buzz-desktop 2>/dev/null || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid"
    return 0
  fi
  pgrep -f 'target/debug/buzz-desktop' 2>/dev/null | while read -r p; do
    if [[ "$(ps -p "$p" -o comm= 2>/dev/null)" == "buzz-desktop" ]]; then
      echo "$p"
    fi
  done
}

desktop_running() {
  [[ -n "$(buzz_desktop_pids)" ]] && curl -fsS "$(vite_url)" >/dev/null 2>&1
}

launcher_pid() {
  if [[ -f "$PID_FILE" ]]; then
    cat "$PID_FILE" 2>/dev/null || true
  fi
}

launcher_running() {
  local pid
  pid="$(launcher_pid)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

mark_ready() {
  date +%s >"$READY_AT_FILE"
}

within_watchdog_grace() {
  if [[ ! -f "$READY_AT_FILE" ]]; then
    return 1
  fi
  local ready_at now
  ready_at="$(cat "$READY_AT_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if (( now - ready_at < WATCHDOG_GRACE_SECS )); then
    return 0
  fi
  return 1
}

kill_process_tree() {
  local pid="$1"
  [[ -z "$pid" ]] && return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  local child
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_process_tree "$child"
  done
  kill "$pid" 2>/dev/null || true
}

log "watchdog started (pid $$)"

while true; do
  sleep "$CHECK_INTERVAL"
  log "heartbeat desktop=$(desktop_running && echo up || echo down) launcher=$(launcher_running && echo up || echo down)"
  if [[ -f "$STOP_FLAG_FILE" ]]; then
    log "stop flag set — exiting"
    exit 0
  fi
  if desktop_running; then
    mark_ready
    continue
  fi
  if launcher_running; then
    # Startup still in progress — only wait during the initial grace window.
    if within_watchdog_grace; then
      continue
    fi
    log "launcher stalled without buzz-desktop — recycling pid $(launcher_pid)"
    kill_process_tree "$(launcher_pid)"
    rm -f "$PID_FILE"
    sleep 2
  fi
  # Desktop and launcher are down — restart (no grace; grace is for startup only).
  log "buzz-desktop exited unexpectedly — restarting"
  rm -f "$STOP_FLAG_FILE"
  "${repo_root}/scripts/run-buzz-desktop.sh" >>"$LOG_FILE" 2>&1 || true
done
