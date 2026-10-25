#!/usr/bin/env bash
# Dev helper: start Fizz/Honey/Pollen buzz-acp harnesses without Buzz Desktop UI.
# Keys are read from buzz-desktop-dev keychain blob (same as desktop hydrate_keys).
set -euo pipefail

BUZZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="${HOME}/Library/Application Support/xyz.block.buzz.app.dev/agents"
RELAY="${BUZZ_RELAY_URL:-wss://pathx.communities.buzz.xyz}"
OWNER="8603d7b8120f44bfba4e48bd000ef6dc91fdfda1e5cbdc4bbd3bd18437b34873"
RELAY_HASH="08c7cb104a5eb7052b93b6c7d0fbc0a3e631e80ea33e0b78b7d2fcb7e6df5c2b"
ACP="${BUZZ_ROOT}/target/debug/buzz-acp"
AGENT="${BUZZ_ROOT}/target/debug/buzz-agent"
MCP="${BUZZ_ROOT}/target/debug/buzz-dev-mcp"
MIROFISH_MCP="${MIROFISH_MCP_COMMAND:-${BUZZ_ROOT}/../../mirofish-mcp-server/scripts/run-stdio.sh}"
MIROFISH_BASE="${MIROFISH_BASE_URL:-http://127.0.0.1:5001}"
LOGDIR="${SUPPORT}/logs"
PIDS_DIR="${SUPPORT}/agent-pids"

mkdir -p "$LOGDIR" "$PIDS_DIR"

# Fizz/Honey/Pollen use BASETEN_MODEL_APIS_BASE=http://127.0.0.1:8765/v1 — shim must be up first.
"${BUZZ_ROOT}/scripts/ensure-baseten-shim.sh" || {
  echo "[start-welcome-team-harnesses] Baseten shim not running — agents will fail LLM calls" >&2
  exit 1
}

export SUPPORT RELAY OWNER RELAY_HASH ACP AGENT MCP MIROFISH_MCP MIROFISH_BASE LOGDIR PIDS_DIR

for bin in "$ACP" "$AGENT"; do
  if [[ ! -x "$bin" ]]; then
    echo "missing $bin — run: cd $BUZZ_ROOT && cargo build -p buzz-acp -p buzz-agent -p buzz-dev-mcp" >&2
    exit 1
  fi
done

export PYTHONPATH=""
python3 <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path

support = Path(os.environ["SUPPORT"])
relay = os.environ["RELAY"]
owner = os.environ["OWNER"]
relay_hash = os.environ["RELAY_HASH"]
acp = os.environ["ACP"]
agent = os.environ["AGENT"]
mcp = os.environ["MCP"]
mirofish_mcp = os.environ.get("MIROFISH_MCP", "")
mirofish_base = os.environ.get("MIROFISH_BASE", "http://127.0.0.1:5001")
logdir = Path(os.environ["LOGDIR"])
pids_dir = Path(os.environ["PIDS_DIR"])

names = {
    "2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f": "Fizz",
    "fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f": "Honey",
    "b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322": "Pollen",
}

records = {r["pubkey"]: r for r in json.loads((support / "managed-agents.json").read_text()) if r.get("pubkey") in names}
global_cfg = json.loads((support / "global-agent-config.json").read_text())
global_env = global_cfg.get("env_vars") or {}
model = global_cfg.get("model") or "moonshotai/Kimi-K2.6"
provider = global_cfg.get("provider") or "baseten"

def apply_baseten_env(env: dict, model_name: str) -> None:
    """Mirror desktop managed_agents/baseten.rs apply_baseten_env."""
    env["BUZZ_BASETEN_NATIVE"] = "1"
    env["BUZZ_AGENT_PROVIDER"] = "openai"
    env["BUZZ_AGENT_MODEL"] = model_name
    env["OPENAI_COMPAT_MODEL"] = model_name
    env["OPENAI_COMPAT_API"] = "chat"
    api_key = env.get("BASETEN_API_KEY") or env.get("OPENAI_COMPAT_API_KEY")
    if api_key:
        env["OPENAI_COMPAT_API_KEY"] = api_key
    base = (
        env.get("OPENAI_COMPAT_BASE_URL")
        or env.get("BASETEN_PROXY_BASE_URL")
        or env.get("BASETEN_MODEL_APIS_BASE")
    )
    if base:
        base = base.rstrip("/")
        if not base.endswith("/v1"):
            base = f"{base}/v1"
        env["OPENAI_COMPAT_BASE_URL"] = base

import subprocess as sp
blob_raw = sp.check_output(
    ["security", "find-generic-password", "-s", "buzz-desktop-dev", "-a", "secrets", "-w"],
    text=True,
)
blob = json.loads(blob_raw)

started = []
def stop_existing_harnesses(nsec: str, name: str) -> None:
    """Kill stray buzz-acp processes for this agent key (desktop + CLI duplicates)."""
    try:
        out = sp.check_output(["pgrep", "-f", f"buzz-acp.*--private-key {nsec}"], text=True)
    except sp.CalledProcessError:
        return
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pid = int(line)
            os.kill(pid, 15)
            print(f"{name}: stopped duplicate harness pid {pid}")
        except (OSError, ValueError):
            pass

for pk, name in names.items():
    pid_file = pids_dir / f"{pk}.pid"
    rec = records[pk]
    nsec = blob.get(f"agent:{pk}")
    if not nsec:
        print(f"{name}: no key in keychain blob", file=sys.stderr)
        sys.exit(1)

    stop_existing_harnesses(nsec, name)
    pid_file.unlink(missing_ok=True)

    log = logdir / f"{pk}__{relay_hash}.log"
    with log.open("a") as lf:
        lf.write(f"\n=== CLI start {name} ({pk}) at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} ===\n")

    env = os.environ.copy()
    env.update(global_env)
    env["BUZZ_PRIVATE_KEY"] = nsec
    env["BUZZ_RELAY_URL"] = relay
    env["BUZZ_ACP_AGENT_COMMAND"] = agent
    env["BUZZ_ACP_AGENT_ARGS"] = ""
    env["BUZZ_ACP_MCP_COMMAND"] = mcp if Path(mcp).exists() else ""
    env["BUZZ_ACP_AGENTS"] = str(rec.get("parallelism") or 10)
    env["BUZZ_ACP_RELAY_OBSERVER"] = "true"
    env["BUZZ_ACP_MODEL"] = model
    if provider == "baseten":
        apply_baseten_env(env, model)
    else:
        env["BUZZ_AGENT_MODEL"] = model
        env["BUZZ_AGENT_PROVIDER"] = provider
    env["BUZZ_ACP_MULTIPLE_EVENT_HANDLING"] = "steer"
    env["BUZZ_ACP_DEDUP"] = "queue"
    env["BUZZ_AGENT_THINKING_EFFORT"] = global_env.get("BUZZ_AGENT_THINKING_EFFORT", "xhigh")
    # Reply guard: block end_turn until the model invokes buzz-dev-mcp `shell` with
    # `buzz messages send` (assistant text is never published to the relay).
    # Mesh agents get this via relay_mesh_process_env; Baseten/OpenAI harnesses need it explicitly.
    env.setdefault("BUZZ_AGENT_REQUIRE_REPLY", "1")
    env.setdefault("BUZZ_ACP_PERMISSION_MODE", "bypassPermissions")
    env["RUST_LOG"] = "info"
    if rec.get("system_prompt"):
        env["BUZZ_ACP_SYSTEM_PROMPT"] = rec["system_prompt"]
    if rec.get("auth_tag"):
        env["BUZZ_AUTH_TAG"] = rec["auth_tag"]

    respond = rec.get("respond_to") or "anyone"
    env["BUZZ_ACP_RESPOND_TO"] = respond
    if respond == "allowlist":
        allow = rec.get("respond_to_allowlist") or []
        env["BUZZ_ACP_RESPOND_TO_ALLOWLIST"] = ",".join(allow)
    else:
        env.pop("BUZZ_ACP_RESPOND_TO_ALLOWLIST", None)

    cmd = [
        acp,
        "--relay-url", relay,
        "--private-key", nsec,
        "--agent-owner", owner,
        "--agent-command", agent,
        "--agents", env["BUZZ_ACP_AGENTS"],
        "--respond-to", respond,
    ]
    if respond == "allowlist":
        cmd.extend(["--respond-to-allowlist", env["BUZZ_ACP_RESPOND_TO_ALLOWLIST"]])
    if rec.get("system_prompt"):
        cmd.extend(["--system-prompt", rec["system_prompt"]])
    if Path(mcp).exists():
        cmd.extend(["--mcp-command", mcp])
    if mirofish_mcp and Path(mirofish_mcp).exists():
        env["BUZZ_ACP_MIROFISH_MCP_COMMAND"] = mirofish_mcp
        env["BUZZ_ACP_MIROFISH_BASE_URL"] = mirofish_base
        env["MIROFISH_BASE_URL"] = mirofish_base
        cmd.extend(["--mirofish-mcp-command", mirofish_mcp, "--mirofish-base-url", mirofish_base])
    env.setdefault("SURREALDB_URL", "http://127.0.0.1:8001")
    env.setdefault("TRINO_HOST", "http://127.0.0.1:8080")
    env.setdefault("SCENARIO_SURREAL_NS", "sim")
    env.setdefault("BUZZ_SCENARIO_SURREAL_DB", "buzz_mirofish_scenario")
    env.setdefault("BUZZ_SCENARIO_ID", "buzz_mirofish_scenario")
    env.setdefault("TOOL_BACKEND", "replay")
    cmd.extend(["--permission-mode", "bypassPermissions"])

    with log.open("ab", buffering=0) as out:
        proc = subprocess.Popen(
            cmd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=out,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    pid_file.write_text(str(proc.pid))
    started.append((name, proc.pid))
    print(f"{name}: started pid {proc.pid} → {log}")

if not started:
    sys.exit(0)
print("waiting 8s for relay subscribe…")
time.sleep(8)
PY
