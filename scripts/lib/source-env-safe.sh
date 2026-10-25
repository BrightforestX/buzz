#!/usr/bin/env bash
# Safely export KEY=VALUE pairs from a .env file (handles spaces, =, commas in values).
#
# Usage:
#   source scripts/lib/source-env-safe.sh
#   source_env_file "${BUZZ_ROOT}/.env"

source_env_file() {
  local env_file="${1:?env file path required}"
  [[ -f "$env_file" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  eval "$(python3 - "$env_file" <<'PY'
import shlex
import sys
from pathlib import Path

def parse_env(text: str):
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        yield key, val

for key, val in parse_env(Path(sys.argv[1]).read_text()):
    print(f"export {shlex.quote(key)}={shlex.quote(val)}")
PY
)"
  set +a
}
