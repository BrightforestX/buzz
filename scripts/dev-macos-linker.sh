#!/usr/bin/env bash
# macOS linker wrapper: forward to clang, then codesign buzz-desktop debug binaries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REAL_CC="${BUZZ_DEV_LINKER_CC:-$(xcrun -f clang)}"
"$REAL_CC" "$@"
status=$?

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

if [[ "$(uname)" != Darwin ]] || [[ "${BUZZ_DEV_CODESIGN:-1}" == "0" ]]; then
  exit 0
fi

out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$arg"
    break
  fi
  prev="$arg"
done

if [[ -z "$out" || "$(basename "$out")" != "buzz-desktop" ]]; then
  exit 0
fi

if [[ "$out" != *"/debug/"* ]]; then
  exit 0
fi

echo "dev-macos-linker: codesigning $out" >&2
"$ROOT/scripts/codesign-dev-desktop.sh" "$out" || true
exit 0
