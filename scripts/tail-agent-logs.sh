#!/usr/bin/env bash
# Tail Welcome Team agent harness logs (buzz-acp) from Buzz Dev app support dir.
set -euo pipefail

LOGDIR="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents/logs"
OWNER="${BUZZ_OWNER_PUBKEY:-08c7cb104a5eb7052b93b6c7d0fbc0a3e631e80ea33e0b78b7d2fcb7e6df5c2b}"

declare -A AGENTS=(
  [2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f]=Fizz
  [fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f]=Honey
  [b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322]=Pollen
)

files=()
for pk in "${!AGENTS[@]}"; do
  f="${LOGDIR}/${pk}__${OWNER}.log"
  if [[ -f "$f" ]]; then
    files+=("$f")
    echo "# ${AGENTS[$pk]} -> $f"
  else
    echo "# ${AGENTS[$pk]}: log not found ($f)" >&2
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No agent log files found under $LOGDIR" >&2
  exit 1
fi

echo "# tail -f (${#files[@]} files). Start agents in Buzz Desktop → Agents to see new lines."
exec tail -n 40 -f "${files[@]}"
