#!/usr/bin/env bash
# Idempotent Vite starter for Tauri beforeDevCommand.
# If the dev server is already healthy on the port, exit 0 so restarts do not fail
# with "Port already in use" (--strictPort).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}/desktop"

if ! rg -q 'scenariosRouteImport' src/app/routeTree.gen.ts 2>/dev/null; then
  echo "Regenerating route tree (missing /scenarios)..."
  node ./scripts/generate-route-tree.mjs
fi

port="${BUZZ_VITE_PORT:-37333}"
url="http://localhost:${port}/"

if curl -fsS "$url" >/dev/null 2>&1; then
  exit 0
fi

exec ./node_modules/.bin/vite --port "$port" --strictPort
