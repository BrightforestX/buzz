#!/usr/bin/env bash
# Stop Fizz/Honey/Pollen buzz-acp harnesses started by start-welcome-team-harnesses.sh.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents"
PIDS_DIR="${SUPPORT}/agent-pids"

FIZZ_PK="2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f"
HONEY_PK="fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f"
POLLEN_PK="b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322"

stop_pid_file() {
  local name="$1" pk="$2"
  local pid_file="${PIDS_DIR}/${pk}.pid"
  if [[ ! -f "$pid_file" ]]; then
    echo "${name}: no pid file"
    return 0
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    echo "${name}: stopped pid ${pid}"
  else
    echo "${name}: stale pid file"
  fi
  rm -f "$pid_file"
}

for entry in "Fizz:${FIZZ_PK}" "Honey:${HONEY_PK}" "Pollen:${POLLEN_PK}"; do
  IFS=: read -r name pk <<<"$entry"
  stop_pid_file "$name" "$pk"
done

# Kill any stray buzz-acp for welcome team agents.
for name in Fizz Honey Pollen; do
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" 2>/dev/null || true
    echo "${name}: stopped stray buzz-acp pid ${pid}"
  done < <(pgrep -f "buzz-acp.*You are ${name}," 2>/dev/null || true)
done

echo "Welcome team harnesses stopped."
