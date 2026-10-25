#!/usr/bin/env bash
# Buzz-side entry: source canonical stack-activity helpers from ontology-stack.
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STACK_ONTOLOGY_ROOT="$(cd "${BUZZ_ROOT}/../../infrastructure/digitalocean/ontology-stack" && pwd)"
# shellcheck source=/dev/null
source "${STACK_ONTOLOGY_ROOT}/scripts/lib/stack-activity.sh"
