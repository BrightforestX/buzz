#!/usr/bin/env bash
# Pre-deploy checks for Buzz relay (Fly) + Railway DB dependencies.
# Does not print secret values. Exit 1 if deploy would likely crash-loop.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${BUZZ_ROOT}/scripts/lib/source-env-safe.sh"
source_env_file "${BUZZ_ROOT}/.env"

errors=0

fail() {
  echo "[preflight] FAIL: $*" >&2
  errors=$((errors + 1))
}

ok() {
  echo "[preflight] OK: $*"
}

warn() {
  echo "[preflight] WARN: $*" >&2
}

is_placeholder_url() {
  local val="$1"
  [[ -z "$val" ]] && return 0
  [[ "$val" == *CHANGE_ME* ]] && return 0
  [[ "$val" == *:PORT* ]] && return 0
  [[ "$val" == *containers-us-west-xxx* ]] && return 0
  [[ "$val" == *containers-us-west-yyy* ]] && return 0
  return 1
}

read_secrets_key() {
  local key="$1"
  local secrets_file="${BUZZ_ROOT}/deploy/fly/secrets.env"
  [[ -f "$secrets_file" ]] || return 1
  grep -E "^${key}=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- || true
}

# --- Railway ---
export RAILWAY_TOKEN="${RAILWAY_API_TOKEN:-${RAILWAY_TOKEN:-}}"
if [[ -z "$RAILWAY_TOKEN" ]]; then
  fail "RAILWAY_API_TOKEN not set in buzz/.env"
elif railway whoami >/dev/null 2>&1; then
  ok "Railway auth ($(railway whoami 2>/dev/null | tr -d '\n' | head -c 80))"
else
  fail "Railway unauthorized — regenerate account token at https://railway.com/account/tokens and update RAILWAY_API_TOKEN in buzz/.env"
fi

# --- Fly ---
export FLY_API_TOKEN="${FLY_API_TOKEN_PX_BUZZ:-${FLY_API_TOKEN:-}}"
fly_bin=""
if command -v flyctl >/dev/null 2>&1; then
  fly_bin=flyctl
elif command -v fly >/dev/null 2>&1; then
  fly_bin=fly
fi
if [[ -z "$fly_bin" ]]; then
  fail "flyctl/fly not on PATH"
elif "$fly_bin" auth whoami >/dev/null 2>&1; then
  ok "Fly auth ($("$fly_bin" auth whoami 2>/dev/null | tr -d '\n' | head -c 80))"
else
  fail "Fly unauthorized — set FLY_API_TOKEN_PX_BUZZ in buzz/.env or run fly auth login"
fi

# --- secrets.env DATABASE_URL / REDIS_URL (no value printing) ---
secrets_file="${BUZZ_ROOT}/deploy/fly/secrets.env"
if [[ ! -f "$secrets_file" ]]; then
  fail "Missing deploy/fly/secrets.env — copy deploy/fly/env.fly.example and fill Railway TCP proxy URLs"
else
  for key in DATABASE_URL REDIS_URL; do
    val="$(read_secrets_key "$key")"
    if is_placeholder_url "$val"; then
      fail "${key} in secrets.env is missing or still a placeholder — set Railway TCP proxy URL before deploy"
    else
      ok "${key} configured (value not shown)"
    fi
  done
fi

# --- TLS cert ---
app="${FLY_APP_NAME:-buzz-relay-pathx}"
host="${RELAY_PUBLIC_HOST:-relay.pathx.ai}"
if cert_out="$("$fly_bin" certs check "$host" -a "$app" 2>&1)"; then
  if grep -qiE 'Issued|verified and active' <<<"$cert_out"; then
    ok "TLS cert for ${host}"
  else
    warn "TLS cert for ${host} — review: fly certs check ${host} -a ${app}"
  fi
else
  warn "Could not verify TLS cert for ${host} — run: fly certs check ${host} -a ${app}"
fi

if [[ "$errors" -gt 0 ]]; then
  echo "[preflight] ${errors} check(s) failed — fix before ./scripts/deploy-fly-relay.sh deploy" >&2
  exit 1
fi

echo "[preflight] All checks passed — safe to deploy"
exit 0
