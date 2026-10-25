#!/usr/bin/env bash
# Hardened launcher for Buzz desktop standalone dev.
# Survives terminal close via nohup; use --stop / --status to manage.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts_dir="${repo_root}/scripts"
STATE_DIR="${repo_root}/.local"
PID_FILE="${STATE_DIR}/buzz-desktop.pid"
WATCHDOG_PID_FILE="${STATE_DIR}/buzz-desktop-watchdog.pid"
READY_AT_FILE="${STATE_DIR}/buzz-desktop.ready-at"
LOCK_DIR="${STATE_DIR}/buzz-desktop.lock.d"
STOP_FLAG_FILE="${STATE_DIR}/buzz-desktop.stop"
CAFFEINATE_PID_FILE="${STATE_DIR}/buzz-desktop.caffeinate.pid"
LOG_FILE="${STATE_DIR}/buzz-desktop.log"
WATCHDOG_GRACE_SECS=120

ACTION="start"

log() { printf '[run-buzz-desktop] %s\n' "$*"; }
die() { printf '[run-buzz-desktop] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./scripts/run-buzz-desktop.sh [--stop | --status]

  (default)  Start desktop-standalone detached (nohup) if not already running
  --stop     Stop the detached desktop process
  --status   Print desktop/Vite health
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION="stop" ;;
    --status) ACTION="status" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

setup_env() {
  unset CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER \
        CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER \
        CARGO RUSTFLAGS PKG_CONFIG_PATH

  export OPUS_NO_PKG=1
  export BUZZ_RELAY_URL="wss://pathx.communities.buzz.xyz"
  export PATH="${repo_root}/bin:${scripts_dir}/cargo-dev-wrapper:${PATH}"
  export MIROFISH_BASE_URL="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
  export ZEP_SHIM_BASE_URL="${ZEP_SHIM_BASE_URL:-http://127.0.0.1:8100/api/v2}"
  export SURREALDB_URL="${SURREALDB_URL:-http://127.0.0.1:8001}"
  export TRINO_HOST="${TRINO_HOST:-http://127.0.0.1:8080}"
  export SCENARIO_SURREAL_NS="${SCENARIO_SURREAL_NS:-sim}"
  export BUZZ_SCENARIO_SURREAL_DB="${BUZZ_SCENARIO_SURREAL_DB:-buzz_mirofish_scenario}"
  export MIROFISH_EXPERIMENT_DB="${MIROFISH_EXPERIMENT_DB:-mirofish_experiments_v2}"
  export BUZZ_SCENARIO_ID="${BUZZ_SCENARIO_ID:-buzz_mirofish_scenario}"
}

vite_port() {
  (
    cd "$repo_root"
    # shellcheck disable=SC1091
    source "${scripts_dir}/instance-env.sh"
    echo "$BUZZ_VITE_PORT"
  )
}

vite_url() {
  local port
  port="$(vite_port)"
  echo "http://localhost:${port}/"
}

port_listeners() {
  local port="$1"
  lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
}

free_vite_port() {
  local port listeners
  port="$(vite_port)"
  listeners="$(port_listeners "$port")"
  if [[ -z "$listeners" ]]; then
    return 0
  fi
  log "Freeing stale listeners on Vite port ${port} (pids: ${listeners//$'\n'/ })"
  # shellcheck disable=SC2086
  kill ${listeners} 2>/dev/null || true
  sleep 1
  # shellcheck disable=SC2086
  kill -9 ${listeners} 2>/dev/null || true
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

buzz_desktop_pids() {
  local pid
  pid="$(pgrep -x buzz-desktop 2>/dev/null || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid"
    return 0
  fi
  # cargo run target/debug/buzz-desktop (exclude codesign helper scripts).
  pgrep -f 'target/debug/buzz-desktop' 2>/dev/null | while read -r p; do
    if [[ "$(ps -p "$p" -o comm= 2>/dev/null)" == "buzz-desktop" ]]; then
      echo "$p"
    fi
  done
}

desktop_running() {
  local port url pids
  port="$(vite_port)"
  url="$(vite_url)"
  pids="$(buzz_desktop_pids)"
  [[ -n "$pids" ]] && curl -fsS "$url" >/dev/null 2>&1
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
  (( now - ready_at < WATCHDOG_GRACE_SECS ))
}

start_watchdog() {
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    local existing
    existing="$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
      return 0
    fi
    rm -f "$WATCHDOG_PID_FILE"
  fi

  nohup "${scripts_dir}/buzz-desktop-watchdog.sh" >>"$LOG_FILE" 2>&1 &
  echo "$!" >"$WATCHDOG_PID_FILE"
  disown -h "$!" 2>/dev/null || true
}

with_start_lock() {
  if [[ -d "$LOCK_DIR" ]]; then
    local lock_age now mtime
    now="$(date +%s)"
    mtime="$(stat -f '%m' "$LOCK_DIR" 2>/dev/null || stat -c '%Y' "$LOCK_DIR" 2>/dev/null || echo 0)"
    lock_age=$((now - mtime))
    if (( lock_age > 120 )); then
      log "Removing stale start lock (${lock_age}s old)"
      rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another Buzz desktop start is in progress — skipping"
    return 1
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT RETURN
  "$@"
}

stop_caffeinate() {
  if [[ ! -f "$CAFFEINATE_PID_FILE" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null || true)"
  rm -f "$CAFFEINATE_PID_FILE"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

start_caffeinate() {
  local desktop_pid="$1"
  [[ -z "$desktop_pid" ]] && return 0
  stop_caffeinate
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -dims -w "$desktop_pid" >/dev/null 2>&1 &
    echo "$!" >"$CAFFEINATE_PID_FILE"
    disown -h "$!" 2>/dev/null || true
  fi
}

stop_watchdog() {
  if [[ ! -f "$WATCHDOG_PID_FILE" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)"
  rm -f "$WATCHDOG_PID_FILE"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

start_desktop() {
  with_start_lock _start_desktop_impl
}

_start_desktop_impl() {
  setup_env
  mkdir -p "$STATE_DIR"
  cd "$repo_root"

  if [[ "$(uname)" == Darwin ]]; then
    # shellcheck disable=SC1091
    source "${scripts_dir}/instance-env.sh"
    "${scripts_dir}/ensure-dev-codesign-identity.sh" 2>/dev/null || true
    BUZZ_DEV_KEYCHAIN_SETUP_NON_INTERACTIVE=1 \
      "${scripts_dir}/setup-dev-keychain-once.sh" 2>/dev/null || true
    local desktop_bin="${repo_root}/desktop/src-tauri/target/debug/buzz-desktop"
    if [[ -f "$desktop_bin" ]]; then
      "${scripts_dir}/codesign-dev-desktop.sh" "$desktop_bin" 2>/dev/null || true
    fi
  fi

  if [[ -x "${scripts_dir}/ensure-baseten-shim.sh" ]]; then
    if ! "${scripts_dir}/ensure-baseten-shim.sh"; then
      log "WARNING: Baseten LLM shim not running — @Fizz/@Honey/@Pollen will fail until you run: ./scripts/ensure-baseten-shim.sh"
    fi
  fi

  if [[ -f "$PID_FILE" ]]; then
    local stale_pid
    stale_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$stale_pid" ]] && ! kill -0 "$stale_pid" 2>/dev/null; then
      rm -f "$PID_FILE"
    fi
  fi

  rm -f "$STOP_FLAG_FILE"

  if desktop_running; then
    log "Buzz desktop already running (Vite :$(vite_port))"
    mark_ready
    start_watchdog
    return 0
  fi

  # Stale launcher with no buzz-desktop window — tear down before retrying.
  if launcher_running && [[ -z "$(buzz_desktop_pids)" ]]; then
    log "Clearing stale launcher (pid $(launcher_pid))"
    kill_process_tree "$(launcher_pid)"
    rm -f "$PID_FILE"
    sleep 1
  fi

  # Orphaned Vite with no desktop process blocks --strictPort on a fresh start.
  if [[ -z "$(buzz_desktop_pids)" ]] && [[ -n "$(port_listeners "$(vite_port)")" ]]; then
    free_vite_port
  fi

  {
    echo "===== $(date -Iseconds) start desktop-standalone ====="
  } >>"$LOG_FILE"

  log "Starting desktop-standalone detached (log: $LOG_FILE)"
  export BUZZ_TAURI_NO_WATCH=1
  nohup just desktop-standalone >>"$LOG_FILE" 2>&1 &
  local launcher_pid=$!
  echo "$launcher_pid" >"$PID_FILE"
  disown -h "$launcher_pid" 2>/dev/null || true

  local url i=0 desktop_pids
  url="$(vite_url)"
  while (( i < 300 )); do
    if ! kill -0 "$launcher_pid" 2>/dev/null; then
      rm -f "$PID_FILE"
      die "desktop-standalone exited during startup (see $LOG_FILE)"
    fi
    desktop_pids="$(buzz_desktop_pids | tr '\n' ' ' | xargs echo -n 2>/dev/null || true)"
    if [[ -n "$desktop_pids" ]] && curl -fsS "$url" >/dev/null 2>&1; then
      log "Buzz desktop ready ($url, pid ${desktop_pids})"
      mark_ready
      start_caffeinate "${desktop_pids%%$'\n'*}"
      start_watchdog
      osascript -e 'tell application "Buzz Dev" to activate' 2>/dev/null \
        || osascript -e 'tell application "System Events" to tell (first process whose name contains "Buzz") to set frontmost to true' 2>/dev/null \
        || true
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  log "Buzz desktop may still be starting — check $LOG_FILE"
}

stop_desktop() {
  local pid port listeners
  touch "$STOP_FLAG_FILE"
  rm -f "$READY_AT_FILE"
  stop_caffeinate
  stop_watchdog
  port="$(vite_port)"
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping Buzz desktop launcher tree (pid $pid)"
      kill_process_tree "$pid"
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  else
    log "No PID file"
  fi
  listeners="$(port_listeners "$port")"
  if [[ -n "$listeners" ]]; then
    log "Stopping listeners on Vite port ${port}"
    free_vite_port
  fi
  local desktop_pid
  for desktop_pid in $(buzz_desktop_pids); do
    log "Stopping buzz-desktop (pid $desktop_pid)"
    kill "$desktop_pid" 2>/dev/null || true
  done
  sleep 1
  for desktop_pid in $(buzz_desktop_pids); do
    kill -9 "$desktop_pid" 2>/dev/null || true
  done
  if [[ ! -f "$PID_FILE" ]] && [[ -z "$(port_listeners "$port")" ]] && [[ -z "$(buzz_desktop_pids)" ]]; then
    log "Buzz desktop stopped"
  fi
}

cmd_status() {
  local port url
  port="$(vite_port)"
  url="http://localhost:${port}/"
  local desktop_pids
  desktop_pids="$(buzz_desktop_pids)"
  echo "Buzz desktop status:"
  if curl -fsS "$url" >/dev/null 2>&1; then
    printf '  %-14s OK   %s\n' "Vite" "$url"
  else
    printf '  %-14s DOWN %s\n' "Vite" "$url"
  fi
  if [[ -n "$desktop_pids" ]]; then
    printf '  %-14s OK   pid %s\n' "buzz-desktop" "${desktop_pids//$'\n'/ }"
  else
    printf '  %-14s DOWN\n' "buzz-desktop"
  fi
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "  process        running (pid $pid)"
    elif curl -fsS "$url" >/dev/null 2>&1; then
      rm -f "$PID_FILE"
      echo "  process        running (external)"
    else
      rm -f "$PID_FILE"
      echo "  process        not running (removed stale pid $pid)"
    fi
  elif curl -fsS "$url" >/dev/null 2>&1; then
    echo "  process        running (external)"
  else
    echo "  process        not tracked"
  fi
  echo "  log            $LOG_FILE"
}

case "$ACTION" in
  start) start_desktop ;;
  stop) stop_desktop ;;
  status) cmd_status ;;
esac
