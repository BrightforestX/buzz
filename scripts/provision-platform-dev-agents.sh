#!/usr/bin/env bash
# Provision platform-dev managed agent instances (Chain, Tempo, Sandbox, Gate, E2E).
#
# Buzz has no headless `buzz agents create` — instance minting is Buzz Desktop only
# (`create_managed_agent` Tauri). This script audits state, can activate persona
# definitions in the local store, and can add relay channel members once pubkeys exist.
#
# Reference: desktop/src/features/onboarding/welcomeGuide.ts (PLATFORM_DEV_STARTERS)
#
# Usage:
#   ./scripts/provision-platform-dev-agents.sh                 # dry-run audit (default)
#   ./scripts/provision-platform-dev-agents.sh --dry-run
#   ./scripts/provision-platform-dev-agents.sh --activate-personas   # Buzz Desktop CLOSED
#   ./scripts/provision-platform-dev-agents.sh --add-channel-members # needs buzz on PATH
#
# Env:
#   BUZZ_AGENTS_DIR          override app-data agents dir
#   BUZZ_RELAY_URL           relay for new instances (default pathx communities)
#   PRODUCT_DEVELOPMENT_CHANNEL_ID  channel UUID for add-member (spec 011 default)
#
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="${BUZZ_AGENTS_DIR:-${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents}"
MANAGED_AGENTS_JSON="${SUPPORT}/managed-agents.json"
RELAY_URL="${BUZZ_RELAY_URL:-wss://pathx.communities.buzz.xyz}"
PLATFORM_DEV_TEAM_ID="builtin-team:platform-dev"
PRODUCT_DEV_CHANNEL="${PRODUCT_DEVELOPMENT_CHANNEL_ID:-28c8bf26-10fa-42e7-b658-38092562bfe1}"

DRY_RUN=1
ACTIVATE_PERSONAS=0
ADD_CHANNEL_MEMBERS=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --dry-run) DRY_RUN=1 ;;
    --activate-personas) ACTIVATE_PERSONAS=1; DRY_RUN=0 ;;
    --add-channel-members) ADD_CHANNEL_MEMBERS=1; DRY_RUN=0 ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      ;;
  esac
done

if [[ "$ACTIVATE_PERSONAS" -eq 0 && "$ADD_CHANNEL_MEMBERS" -eq 0 && "$DRY_RUN" -eq 1 ]]; then
  : # default dry-run
elif [[ "$ACTIVATE_PERSONAS" -eq 1 && "$ADD_CHANNEL_MEMBERS" -eq 1 ]]; then
  echo "Use --activate-personas and --add-channel-members in separate runs." >&2
  exit 1
fi

if [[ ! -f "$MANAGED_AGENTS_JSON" ]]; then
  echo "managed-agents.json not found: $MANAGED_AGENTS_JSON" >&2
  echo "Start Buzz Desktop once or set BUZZ_AGENTS_DIR." >&2
  exit 1
fi

export MANAGED_AGENTS_JSON RELAY_URL PLATFORM_DEV_TEAM_ID PRODUCT_DEV_CHANNEL
export DRY_RUN ACTIVATE_PERSONAS ADD_CHANNEL_MEMBERS BUZZ_ROOT

python3 <<'PY'
import json, os, subprocess, sys
from pathlib import Path

# Mirrors welcomeGuide.ts PLATFORM_DEV_STARTERS (+ welcome team for context).
PLATFORM_DEV_STARTERS = [
    {"name": "Chain", "personaId": "builtin:chain", "role": "lead"},
    {"name": "Tempo", "personaId": "builtin:tempo", "role": "teammate"},
    {"name": "Sandbox", "personaId": "builtin:sandbox", "role": "teammate"},
    {"name": "Gate", "personaId": "builtin:gate", "role": "teammate"},
    {"name": "E2E", "personaId": "builtin:e2e", "role": "teammate"},
]
WELCOME_STARTERS = [
    {"name": "Fizz", "personaId": "builtin:fizz"},
    {"name": "Honey", "personaId": "builtin:honey"},
    {"name": "Pollen", "personaId": "builtin:bumble"},
]

managed_path = Path(os.environ["MANAGED_AGENTS_JSON"])
relay_url = os.environ["RELAY_URL"].rstrip("/")
team_id = os.environ["PLATFORM_DEV_TEAM_ID"]
channel_id = os.environ["PRODUCT_DEV_CHANNEL"]
dry_run = os.environ.get("DRY_RUN", "1") == "1"
activate = os.environ.get("ACTIVATE_PERSONAS", "0") == "1"
add_members = os.environ.get("ADD_CHANNEL_MEMBERS", "0") == "1"

records = json.loads(managed_path.read_text())
if not isinstance(records, list):
    records = records.get("agents", [])

def norm_relay(url):
    return (url or "").strip().rstrip("/")

def is_instance(rec):
    pk = (rec.get("pubkey") or "").strip()
    return len(pk) == 64

def persona_slug(rec):
    return rec.get("persona_id") or rec.get("slug")

def pick_instance(persona_id):
    matches = [
        r for r in records
        if is_instance(r)
        and persona_slug(r) == persona_id
        and norm_relay(r.get("relay_url")) == relay_url
    ]
    if not matches:
        matches = [
            r for r in records
            if is_instance(r) and persona_slug(r) == persona_id
        ]
    # Prefer platform-dev team, then any instance.
    matches.sort(
        key=lambda r: (
            0 if (r.get("team_id") or r.get("teamId")) == team_id else 1,
            r.get("name") or "",
        )
    )
    return matches[0] if matches else None

def definition_record(persona_id):
    for rec in records:
        if not is_instance(rec) and persona_slug(rec) == persona_id:
            return rec
    return None

print(f"Store: {managed_path}")
print(f"Relay: {relay_url}")
print(f"Platform team id: {team_id}")
print()

if activate:
    changed = False
    for starter in PLATFORM_DEV_STARTERS:
        rec = definition_record(starter["personaId"])
        if rec is None:
            print(f"WARN: no definition row for {starter['name']} ({starter['personaId']}) — rebuild Buzz Desktop")
            continue
        if not rec.get("is_active", False):
            print(f"activate persona definition: {starter['name']} ({starter['personaId']})")
            rec["is_active"] = True
            changed = True
        else:
            print(f"already active: {starter['name']} ({starter['personaId']})")
    if changed and not dry_run:
        managed_path.write_text(json.dumps(records, indent=2) + "\n")
        print("\nWrote persona is_active flags. Reopen Buzz Desktop → Agents to refresh.")
    elif changed:
        print("\n(dry-run) would write is_active flags — pass --activate-personas without --dry-run")
    sys.exit(0)

missing_instances = []
ready = []

print("=== Welcome Team instances (expect 3) ===")
for starter in WELCOME_STARTERS:
    inst = pick_instance(starter["personaId"])
    if inst:
        print(f"  OK  {starter['name']:8} pubkey={inst['pubkey']} team={inst.get('team_id')}")
    else:
        print(f"  MISS {starter['name']:8} persona={starter['personaId']}")

print()
print("=== Platform dev instances (need 5) ===")
for starter in PLATFORM_DEV_STARTERS:
    inst = pick_instance(starter["personaId"])
    defn = definition_record(starter["personaId"])
    active = defn.get("is_active") if defn else None
    if inst:
        team = inst.get("team_id") or inst.get("teamId")
        team_note = "" if team == team_id else f" (team={team or 'none'}, want {team_id})"
        print(f"  OK  {starter['name']:8} pubkey={inst['pubkey']}{team_note}")
        ready.append((starter["name"], inst["pubkey"]))
    else:
        print(f"  MISS {starter['name']:8} persona={starter['personaId']} is_active={active}")
        missing_instances.append(starter)

print()
if missing_instances:
    print("Buzz CLI cannot create managed instances. Available subcommands:")
    print("  buzz agents draft-create   (opens Desktop owner-review draft — not batch create)")
    print("  buzz agents draft-update | archive | unarchive | archived")
    print()
    print("Create missing instances in Buzz Desktop:")
    print("  1. Quit Buzz Desktop if you ran --activate-personas")
    print("  2. Open Buzz Desktop → sidebar Agents (library)")
    print("  3. If a persona card is missing: Agents → + New agent → Community catalog")
    print("     → select Chain / Tempo / Sandbox / Gate / E2E → Add to My Agents")
    print("  4. On each platform-dev persona card, click Start (play) — mints a managed instance")
    print(f"  5. Optional: edit instance team to {team_id} in profile if not set at create")
    print("  6. Re-run this script (dry-run) to print pubkeys")
    print()
    print("Or run: ./scripts/provision-platform-dev-agents.sh --activate-personas")
    print("       (Buzz closed) then create instances from the UI as above.")

if add_members:
    if not ready:
        print("No platform-dev instances with pubkeys — create them in Desktop first.", file=sys.stderr)
        sys.exit(1)
    buzz = "buzz"
    try:
        subprocess.run([buzz, "--version"], capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("buzz CLI not on PATH. Build: cd buzz && cargo build -p buzz-cli", file=sys.stderr)
        sys.exit(1)
    print(f"Adding {len(ready)} pubkeys to channel {channel_id} …")
    for name, pk in ready:
        cmd = [
            buzz, "channels", "add-member",
            "--channel", channel_id,
            "--pubkey", pk,
        ]
        print(f"  {name}: {' '.join(cmd)}")
        if not dry_run:
            subprocess.run(cmd, check=False)
    sys.exit(0)

if ready:
    print("Pubkeys for #product-development (buzz channels add-member):")
    for name, pk in ready:
        print(f"  {name}: {pk}")
    print()
    print("Add all:")
    print(f"  source {os.environ['BUZZ_ROOT']}/scripts/relay-env.sh")
    print(f"  ./scripts/provision-platform-dev-agents.sh --add-channel-members")

if missing_instances and dry_run:
    sys.exit(2)
PY
