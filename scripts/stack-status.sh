#!/usr/bin/env bash
set -euo pipefail
BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ONTOLOGY_ROOT="$(cd "${BUZZ_ROOT}/../../infrastructure/digitalocean/ontology-stack" && pwd)"
export BUZZ_ROOT
exec "${ONTOLOGY_ROOT}/scripts/stack-status.sh" "$@"
