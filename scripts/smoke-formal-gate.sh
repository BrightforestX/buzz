#!/usr/bin/env bash
# Buzz S04 formal Verify wire smoke — hook regressions + upstream formal subset.
# No cloud keys; fails closed on test errors.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== smoke-formal-gate: Buzz durable agent platform (S04 wire) =="

echo "-- buzz-agent ontology gate integration --"
cargo test -p buzz-agent ontology_gate --quiet

echo "-- buzz-agent MCP hook regressions --"
cargo test -p buzz-agent hook_ --quiet

UPSTREAM_SMOKE="../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh"
if [[ -f "$UPSTREAM_SMOKE" ]]; then
  echo "-- upstream platform formal smoke --"
  bash "$UPSTREAM_SMOKE"
else
  echo "WARN: upstream smoke not found at $UPSTREAM_SMOKE"
  exit 1
fi

echo "== smoke-formal-gate: PASS =="
