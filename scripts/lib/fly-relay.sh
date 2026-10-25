#!/usr/bin/env bash
# Fly relay machine helpers — wake, sleep, status.
# Sourced by deploy-fly-relay.sh and ontology-stack lifecycle scripts.

fly_relay__cmd() {
  if [[ -n "${FLYCTL:-}" ]]; then
    printf '%s\n' "$FLYCTL"
    return 0
  fi
  if command -v flyctl >/dev/null 2>&1; then
    printf '%s\n' flyctl
    return 0
  fi
  if command -v fly >/dev/null 2>&1; then
    printf '%s\n' fly
    return 0
  fi
  echo "fly-relay: install flyctl (https://fly.io/docs/hands-on/install-flyctl/)" >&2
  return 1
}

fly_relay_app() {
  printf '%s\n' "${FLY_APP_NAME:-buzz-relay-pathx}"
}

fly_relay_config() {
  local buzz root
  buzz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  root="${FLY_CONFIG:-${buzz}/deploy/fly/fly.toml}"
  if [[ ! -f "$root" ]]; then
    echo "fly-relay: missing fly.toml at $root" >&2
    return 1
  fi
  printf '%s\n' "$root"
}

fly_relay_machine_ids() {
  local fly app json
  fly="$(fly_relay__cmd)" || return 1
  app="$(fly_relay_app)"
  json="$("$fly" machine list -a "$app" --json 2>/dev/null || true)"
  if [[ -z "$json" || "$json" == "[]" ]]; then
    return 0
  fi
  python3 - "$json" <<'PY'
import json, sys
try:
    data = json.loads(sys.argv[1])
except json.JSONDecodeError:
    raise SystemExit(0)
for m in data:
    mid = m.get("id")
    if mid:
        print(mid)
PY
}

fly_relay_any_running() {
  local fly app json
  fly="$(fly_relay__cmd)" || return 1
  app="$(fly_relay_app)"
  json="$("$fly" machine list -a "$app" --json 2>/dev/null || true)"
  python3 - "$json" <<'PY'
import json, sys
raw = sys.argv[1]
if not raw or raw == "[]":
    raise SystemExit(1)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)
for m in data:
    state = (m.get("state") or "").lower()
    if state in ("started", "starting", "created"):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

fly_relay_wake() {
  local fly app config ids id started=0
  fly="$(fly_relay__cmd)" || return 1
  app="$(fly_relay_app)"
  config="$(fly_relay_config)" || return 1

  if ! "$fly" apps list --json 2>/dev/null | python3 -c "import json,sys; app=sys.argv[1]; data=json.load(sys.stdin); sys.exit(0 if any(a.get('Name')==app or a.get('name')==app for a in data) else 1)" "$app" 2>/dev/null; then
    echo "[fly-relay] app $app not found — run deploy-fly-relay.sh bootstrap" >&2
    return 1
  fi

  mapfile -t ids < <(fly_relay_machine_ids)
  if [[ ${#ids[@]} -eq 0 ]]; then
    echo "[fly-relay] no machines — deploying…"
    "$fly" deploy --config "$config" -a "$app" --ha=false
    return 0
  fi

  for id in "${ids[@]}"; do
    [[ -z "$id" ]] && continue
    if "$fly" machine start "$id" -a "$app" 2>/dev/null; then
      started=1
      echo "[fly-relay] started machine $id"
    fi
  done

  if [[ "$started" -eq 0 ]]; then
    echo "[fly-relay] machines already running or start skipped"
  fi
}

fly_relay_sleep() {
  local fly app ids id stopped=0
  fly="$(fly_relay__cmd)" || return 1
  app="$(fly_relay_app)"
  mapfile -t ids < <(fly_relay_machine_ids)
  if [[ ${#ids[@]} -eq 0 ]]; then
    echo "[fly-relay] no machines to stop"
    return 0
  fi
  for id in "${ids[@]}"; do
    [[ -z "$id" ]] && continue
    if "$fly" machine stop "$id" -a "$app" 2>/dev/null; then
      stopped=1
      echo "[fly-relay] stopped machine $id"
    fi
  done
  if [[ "$stopped" -eq 0 ]]; then
    echo "[fly-relay] no running machines stopped"
  fi
}

fly_relay_status_line() {
  local fly app json
  fly="$(fly_relay__cmd)" || return 1
  app="$(fly_relay_app)"
  json="$("$fly" machine list -a "$app" --json 2>/dev/null || echo '[]')"
  python3 - "$json" "$app" <<'PY'
import json, sys
raw, app = sys.argv[1], sys.argv[2]
try:
    machines = json.loads(raw) if raw else []
except json.JSONDecodeError:
    machines = []
if not machines:
    print(f"Fly app {app}: no machines (run deploy)")
    raise SystemExit(0)
for m in machines:
    print(f"Fly machine {m.get('id','?')}: {m.get('state','?')} region={m.get('region','?')}")
PY
}
