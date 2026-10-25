#!/usr/bin/env bash
# Hardened launcher for Buzz mobile release on a physical device.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_udid="${BUZZ_DEVICE_UDID:-00008130-000A148E22F2001C}"
relay_url="${BUZZ_RELAY_URL:-wss://pathx.communities.buzz.xyz}"

"${repo_root}/scripts/mobile-worktree-overrides.sh"

cd "${repo_root}/mobile"
unset GIT_DIR GIT_WORK_TREE
export PATH="${repo_root}/bin:${PATH}"

exec "${repo_root}/bin/flutter" run --release \
  --dart-define=BUZZ_RELAY_URL="${relay_url}" \
  -d "${device_udid}" \
  "$@"
