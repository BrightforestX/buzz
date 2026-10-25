#!/usr/bin/env bash
# Ensure local Baseten OpenAI shim (http://127.0.0.1:8765/v1) is running for buzz-agent.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "--stop" ]]; then
  PID_FILE="${BUZZ_ROOT}/.local/baseten-shim.pid"
  if [[ -f "$PID_FILE" ]]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$old_pid" 2>/dev/null || true
      echo "[ensure-baseten-shim] stopped shim pid $old_pid"
    fi
    rm -f "$PID_FILE"
  else
    echo "[ensure-baseten-shim] no pid file"
  fi
  exit 0
fi

SHIM="${BUZZ_ROOT}/../gpu-inference-stack/scripts/buzz-chain-openai-shim.py"
SUPPORT="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents"
GLOBAL_CFG="${SUPPORT}/global-agent-config.json"
LOGDIR="${BUZZ_ROOT}/.local"
SHIM_LOG="${LOGDIR}/baseten-shim.log"
PID_FILE="${LOGDIR}/baseten-shim.pid"
DEBUG_LOG="/Users/clifforddalsoniii/Documents/Personal/employment/resume/.cursor/debug-7a21c8.log"
PORT="${BUZZ_CHAIN_SHIM_PORT:-8765}"
HOST="${BUZZ_CHAIN_SHIM_HOST:-127.0.0.1}"

mkdir -p "$LOGDIR"

debug_log() {
  local msg="$1" hid="$2" extra="${3:-{}}"
  # #region agent log
  printf '{"sessionId":"7a21c8","hypothesisId":"%s","location":"ensure-baseten-shim.sh","message":"%s","data":%s,"timestamp":%s}\n' \
    "$hid" "$msg" "$extra" "$(date +%s000)" >>"$DEBUG_LOG" 2>/dev/null || true
  # #endregion
}

if curl -sf "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
  echo "[ensure-baseten-shim] already up http://${HOST}:${PORT}/v1"
  debug_log "shim_already_up" "H1" "{\"port\":${PORT}}"
  exit 0
fi

if [[ ! -f "$SHIM" ]]; then
  echo "[ensure-baseten-shim] missing shim: $SHIM" >&2
  debug_log "shim_script_missing" "H1" "{\"path\":\"$SHIM\"}"
  exit 1
fi

if [[ -z "${BASETEN_API_KEY:-}" ]] && [[ -f "$GLOBAL_CFG" ]]; then
  BASETEN_API_KEY="$(python3 -c "import json; print(json.load(open('$GLOBAL_CFG')).get('env_vars',{}).get('BASETEN_API_KEY',''))")"
  export BASETEN_API_KEY
fi

if [[ -z "${BASETEN_API_KEY:-}" ]]; then
  echo "[ensure-baseten-shim] BASETEN_API_KEY not set and not in $GLOBAL_CFG" >&2
  debug_log "missing_api_key" "H1" "{}"
  exit 1
fi

export BUZZ_CHAIN_LOCAL="${BUZZ_CHAIN_LOCAL:-1}"
export BUZZ_CHAIN_SHIM_HOST="$HOST"
export BUZZ_CHAIN_SHIM_PORT="$PORT"

# Stop stale pid only when the port is not serving (avoid killing a healthy listener).
if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "[ensure-baseten-shim] stopping stale shim pid $old_pid"
    kill "$old_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$old_pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

echo "[ensure-baseten-shim] starting shim → $SHIM_LOG"
debug_log "shim_starting" "H2" "{\"port\":${PORT},\"log\":\"$SHIM_LOG\"}"

# start_new_session=True (same as welcome-team harnesses) so the shim survives terminal close.
python3 <<PY
import os, subprocess, sys, time
from pathlib import Path

shim = Path("${SHIM}")
log_path = Path("${SHIM_LOG}")
pid_file = Path("${PID_FILE}")
host = os.environ["BUZZ_CHAIN_SHIM_HOST"]
port = int(os.environ["BUZZ_CHAIN_SHIM_PORT"])

env = os.environ.copy()
with log_path.open("a") as logf:
    logf.write(f"\n=== shim start {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} ===\n")
    proc = subprocess.Popen(
        [sys.executable, str(shim)],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=logf,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
pid_file.write_text(str(proc.pid))
print(proc.pid)
PY

new_pid="$(cat "$PID_FILE")"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if ! kill -0 "$new_pid" 2>/dev/null; then
    echo "[ensure-baseten-shim] shim exited early (pid $new_pid) — see $SHIM_LOG" >&2
    tail -10 "$SHIM_LOG" 2>/dev/null || true
    debug_log "shim_exited_early" "H2" "{\"pid\":${new_pid}}"
    exit 1
  fi
  if curl -sf "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
    echo "[ensure-baseten-shim] ready http://${HOST}:${PORT}/v1 (pid $new_pid)"
    debug_log "shim_started" "H2" "{\"port\":${PORT},\"pid\":${new_pid}}"
    exit 0
  fi
  sleep 0.5
done

echo "[ensure-baseten-shim] shim failed to become ready — see $SHIM_LOG" >&2
tail -10 "$SHIM_LOG" 2>/dev/null || true
debug_log "shim_start_failed" "H2" "{\"pid\":${new_pid},\"log\":\"$SHIM_LOG\"}"
exit 1
