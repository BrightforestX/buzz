#!/usr/bin/env bash
# Smoke test: PathX relay (HTTP + WSS), Baseten shim, agent harnesses, optional agent pings.
# Monitor-only — does not restart Buzz desktop.
#
# Usage:
#   ./scripts/test-agents-and-relay.sh           # quick checks
#   ./scripts/test-agents-and-relay.sh --ping    # include @mention pings + wait for turns
#   ./scripts/test-agents-and-relay.sh --json    # machine-readable summary line

set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${BUZZ_ROOT}/.local/agents-relay-health.log"
DO_PING=0
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ping) DO_PING=1 ;;
    --json) JSON=1 ;;
    -h|--help)
      echo "Usage: $0 [--ping] [--json]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "${BUZZ_ROOT}/.local"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail=0
relay_communities=0
relay_pathx=0
wss_communities=0
wss_pathx=0
shim=0
desktop=0
fizz=0
honey=0
pollen=0
agent_turns=0

_log() {
  if [[ "$JSON" -eq 0 ]]; then
    echo "$*"
  fi
  echo "[$ts] $*" >>"$LOG"
}

# HTTP NIP-11
if curl -fsS -o /dev/null "https://pathx.communities.buzz.xyz/"; then
  relay_communities=1
  _log "relay HTTP pathx.communities: OK"
else
  _log "relay HTTP pathx.communities: FAIL"
  fail=1
fi

if curl -fsS -o /dev/null "https://relay.pathx.ai/"; then
  relay_pathx=1
  _log "relay HTTP relay.pathx.ai: OK"
else
  _log "relay HTTP relay.pathx.ai: FAIL"
  fail=1
fi

# WSS subscribe probe
wss_out="$(python3 - "$relay_communities" "$relay_pathx" <<'PY' 2>&1 || true
import json, ssl, sys
try:
    import websocket
except ImportError:
    print("ERR:no-websocket-client")
    sys.exit(1)

def probe(url):
    ws = websocket.create_connection(url, timeout=15, sslopt={"cert_reqs": ssl.CERT_REQUIRED})
    ws.send(json.dumps(["REQ", "health-probe", {"kinds": [1], "limit": 1}]))
    ws.recv()
    ws.close()
    return "OK"

for label, url in [
    ("communities", "wss://pathx.communities.buzz.xyz"),
    ("pathx", "wss://relay.pathx.ai"),
]:
    try:
        probe(url)
        print(f"{label}:OK")
    except Exception as e:
        print(f"{label}:FAIL:{e}")
PY
)"
while IFS= read -r line; do
  case "$line" in
    communities:OK) wss_communities=1; _log "relay WSS pathx.communities: OK" ;;
    pathx:OK) wss_pathx=1; _log "relay WSS relay.pathx.ai: OK" ;;
    ERR:no-websocket-client) _log "relay WSS: SKIP (pip install websocket-client)" ;;
    communities:FAIL:*) _log "relay WSS pathx.communities: FAIL"; fail=1 ;;
    pathx:FAIL:*) _log "relay WSS relay.pathx.ai: FAIL"; fail=1 ;;
  esac
done <<<"$wss_out"

# Baseten shim
if curl -sf http://127.0.0.1:8765/v1/models >/dev/null 2>&1; then
  shim=1
  _log "baseten shim :8765: OK"
else
  _log "baseten shim :8765: FAIL"
  fail=1
fi

# Buzz desktop (status script, no restart). Avoid pipefail+grep -q SIGPIPE false negative.
desktop_status="$("${BUZZ_ROOT}/scripts/run-buzz-desktop.sh" --status 2>&1 || true)"
if [[ "$desktop_status" =~ buzz-desktop[[:space:]]+OK ]]; then
  desktop=1
  _log "buzz desktop: OK"
else
  _log "buzz desktop: DOWN (not restarting)"
  fail=1
fi

# Agent harness PIDs
PIDS_DIR="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents/agent-pids"
for agent in Fizz:2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f \
               Honey:fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f \
               Pollen:b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322; do
  name="${agent%%:*}"
  pk="${agent##*:}"
  pid_file="${PIDS_DIR}/${pk}.pid"
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    _log "harness ${name}: OK pid $(cat "$pid_file")"
    case "$name" in Fizz) fizz=1 ;; Honey) honey=1 ;; Pollen) pollen=1 ;; esac
  else
    _log "harness ${name}: DOWN"
    fail=1
  fi
done

if [[ "$DO_PING" -eq 1 ]]; then
  export STACK_MONITOR_PING=1
  if "${BUZZ_ROOT}/scripts/ping-product-development-agents.sh" --wait 2>&1 | tee -a "$LOG"; then
    agent_turns=1
  else
    fail=1
  fi
  unset STACK_MONITOR_PING
fi

# Idle sleep monitor (separate from health recovery; never auto-sleep during health ticks).
ONTOLOGY_STACK_ROOT="$(cd "${BUZZ_ROOT}/../../infrastructure/digitalocean/ontology-stack" && pwd)"
if [[ "${HEALTH_LOOP_TICK:-0}" != "1" ]] && [[ -x "${ONTOLOGY_STACK_ROOT}/scripts/stack-idle-monitor.sh" ]]; then
  STACK_BUZZ_ROOT="$BUZZ_ROOT" \
    "${ONTOLOGY_STACK_ROOT}/scripts/stack-idle-monitor.sh" \
    2>&1 | tee -a "$LOG" || true
fi

if [[ "$JSON" -eq 1 ]]; then
  printf '{"ts":"%s","ok":%s,"relay_communities":%s,"relay_pathx":%s,"wss_communities":%s,"wss_pathx":%s,"shim":%s,"desktop":%s,"fizz":%s,"honey":%s,"pollen":%s}\n' \
    "$ts" "$([[ $fail -eq 0 ]] && echo true || echo false)" \
    "$relay_communities" "$relay_pathx" "$wss_communities" "$wss_pathx" \
    "$shim" "$desktop" "$fizz" "$honey" "$pollen"
fi

if [[ "$JSON" -eq 0 ]]; then
  if [[ "$fail" -eq 0 ]]; then
    _log "SUMMARY: ALL CHECKS PASSED"
  else
    _log "SUMMARY: SOME CHECKS FAILED (see above)"
  fi
fi

exit "$fail"
