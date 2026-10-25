#!/usr/bin/env bash
# Monitor Buzz desktop uptime without restarting (watchdog handles recovery).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${repo_root}/.local/buzz-stability.log"
INTERVAL="${1:-60}"
TICKS="${2:-5}"

mkdir -p "${repo_root}/.local"

{
  echo "===== monitor start $(date -Iseconds) interval=${INTERVAL}s ticks=${TICKS} ====="
} >>"$LOG"

for i in $(seq 1 "$TICKS"); do
  sleep "$INTERVAL"
  {
    echo "--- tick ${i}/${TICKS} $(date -Iseconds) ---"
    "${repo_root}/scripts/run-buzz-desktop.sh" --status
    if [[ -f "${repo_root}/.local/buzz-desktop.ready-at" ]]; then
      ready_at="$(cat "${repo_root}/.local/buzz-desktop.ready-at")"
      now="$(date +%s)"
      echo "  uptime_since_ready: $((now - ready_at))s"
    fi
    tail -3 "${repo_root}/.local/buzz-desktop.log" 2>/dev/null | sed 's/^/  log: /'
  } >>"$LOG"
  echo "AGENT_LOOP_TICK_buzz-stability {\"tick\":${i},\"ticks\":${TICKS},\"log\":\"${LOG}\"}"
done

echo "AGENT_LOOP_DONE_buzz-stability {\"result\":\"finished\",\"log\":\"${LOG}\"}"
