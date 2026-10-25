#!/usr/bin/env bash
# Open a new Terminal window running the scenario stack (Hermit + herd script).
# Prefer Docker + log panes: ./scripts/open-scenario-stack-panes.sh
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERD="${BUZZ_ROOT}/scripts/run-scenario-stack-herd.sh"
chmod +x "$HERD"

CMD="cd $(printf '%q' "$BUZZ_ROOT") && . ./bin/activate-hermit 2>/dev/null || true && exec $(printf '%q' "$HERD")"

if [[ "$(uname -s)" == "Darwin" ]] && [[ -d /Applications/Utilities/Terminal.app || -d /System/Applications/Utilities/Terminal.app ]]; then
  osascript -e "tell application \"Terminal\" to activate" \
    -e "tell application \"Terminal\" to do script \"${CMD//\"/\\\"}\""
  echo "Opened scenario stack in a new Terminal window (grant Accessibility to Terminal for tab mode)."
else
  echo "Not macOS Terminal — run in another shell tab:"
  echo "  cd ${BUZZ_ROOT} && . ./bin/activate-hermit && ${HERD}"
fi
