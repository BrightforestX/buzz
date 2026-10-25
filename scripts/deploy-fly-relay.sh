#!/usr/bin/env bash
# Deploy and operate Buzz relay on Fly.io.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/lib/fly-relay.sh"

# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/lib/source-env-safe.sh"
source_env_file "${BUZZ_ROOT}/.env"

usage() {
  cat <<'EOF'
Usage: deploy-fly-relay.sh <command>

Run ./scripts/deploy-preflight.sh before deploy (Railway auth, secrets.env DB URLs, Fly auth, TLS).

Commands:
  bootstrap   Create app + volume (idempotent)
  deploy      fly deploy (image from fly.toml)
  secrets     Import deploy/fly/secrets.env if present
  wake        Start stopped machine(s)
  sleep       Stop all machines (no compute bill)
  status      Machine list + relay HTTP probe
EOF
}

cmd="${1:-}"
case "$cmd" in
  bootstrap)
    fly="$(fly_relay__cmd)"
    app="$(fly_relay_app)"
    region="${FLY_PRIMARY_REGION:-iad}"
    if ! "$fly" apps list --json 2>/dev/null | python3 -c "import json,sys; app=sys.argv[1]; data=json.load(sys.stdin); sys.exit(0 if any(a.get('Name')==app or a.get('name')==app for a in data) else 1)" "$app" 2>/dev/null; then
      echo "[deploy-fly] creating app $app"
      "$fly" apps create "$app" ${FLY_ORG:+--org "$FLY_ORG"}
    else
      echo "[deploy-fly] app $app exists"
    fi
    if ! "$fly" volumes list -a "$app" --json 2>/dev/null | python3 -c "import json,sys; data=json.load(sys.stdin); sys.exit(0 if any(v.get('name')=='buzz_git' for v in data) else 1)" 2>/dev/null; then
      echo "[deploy-fly] creating volume buzz_git in $region"
      "$fly" volumes create buzz_git --size "${FLY_GIT_VOLUME_GB:-10}" --region "$region" -a "$app"
    else
      echo "[deploy-fly] volume buzz_git exists"
    fi
    ;;
  secrets)
    fly="$(fly_relay__cmd)"
    app="$(fly_relay_app)"
    secrets_file="${BUZZ_ROOT}/deploy/fly/secrets.env"
    if [[ ! -f "$secrets_file" ]]; then
      echo "Missing $secrets_file — copy from deploy/fly/env.fly.example" >&2
      exit 1
    fi
    "$fly" secrets import <"$secrets_file" -a "$app"
    ;;
  deploy)
    fly="$(fly_relay__cmd)"
    app="$(fly_relay_app)"
    config="$(fly_relay_config)"
    "$fly" deploy --config "$config" -a "$app" --ha=false
    ;;
  wake)
    fly_relay_wake
    ;;
  sleep)
    fly_relay_sleep
    ;;
  status)
    fly_relay_status_line || true
    relay_url="${RELAY_PUBLIC_URL:-https://relay.pathx.ai}"
    if curl -fsS -o /dev/null --max-time 15 "${relay_url}/_readiness" 2>/dev/null; then
      echo "Relay probe ${relay_url}: UP"
    else
      echo "Relay probe ${relay_url}: DOWN"
    fi
    ;;
  -h|--help|help|"")
    usage
    [[ -n "$cmd" ]] || exit 0
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
