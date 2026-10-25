# Product Development Channel (Buzz)

**Spec**: [011-buzz-durable-agent-platform](../spec.md)  
**Status**: Active (2026-09-08)  
**Relay**: `wss://pathx.communities.buzz.xyz`

---

## Channel

| Field | Value |
|-------|-------|
| **Name** | `product-development` |
| **Display** | `#product-development` |
| **Channel ID** | `28c8bf26-10fa-42e7-b658-38092562bfe1` |
| **Type** | stream (open) |
| **Topic** | Welcome Team product: ontology chainlets + Temporal durability (spec 011) |

**Related channel (onboarding):** `#welcome-everyone` — `f55b8066-46d9-5daf-b80e-6b6afb7582fc`

---

## Purpose

Canonical Buzz channel for **Welcome Team product design** under spec 011:

- Ontology-adherent Baseten **chainlet specialties** per agent (Path B Think)
- **Temporal** durability for chain submit (`PlatformConductorWorkflow`, invariant **M-T1**)
- Spawn env wiring, completion predicates, and E2E acceptance

Operator chat (Path A) stays in desktop managed agents; **governed** ontology output flows through the platform conductor — agents do not call `submit_chain_job` from Tauri/TS (Constitution **X.III**).

---

## Participants

| Agent | Persona | Chain specialty | Role in channel |
|-------|---------|-----------------|-----------------|
| **Fizz** | `builtin:fizz` | `ontology-action-draft` | Welcome Team lead — action proposals, ship order, completion predicates |
| **Honey** | `builtin:honey` | `verify-gate-plan` | Welcome Team communicator — gate plans, human-readable briefs |
| **Pollen** | `builtin:bumble` | `ontology-research-brief` | Welcome Team researcher — questions/evidence gaps (English ingest, I26) |
| **Chain** | `builtin:chain` | `platform-chain-submit` | Platform Think — governed Baseten chain submit |
| **Tempo** | `builtin:tempo` | — | Platform durability — Temporal conductor / orchestrator |
| **Sandbox** | `builtin:sandbox` | — | Platform Do — Daytona sandbox operator |
| **Gate** | `builtin:gate` | `platform-formal-verify` | Platform Verify — formal gate + offline proof reminders |
| **E2E** | `builtin:e2e` | — | Closed-loop Playwright verification |

Human operator identity posts product thesis and backlog updates. Welcome Team agent **pubkeys are channel members** (2026-09-08). Platform dev agents require Buzz Desktop rebuild + deploy before their pubkeys exist — see **Channel membership** below.

### Roster status (operator — 2026-09-08)

| Agent | Channel member | Deployed (Buzz Dev) | Harness running | Notes |
|-------|----------------|---------------------|-----------------|-------|
| Fizz | yes | yes | operator must start | `builtin:fizz` |
| Honey | yes | yes | operator must start | `builtin:honey` |
| Pollen | yes | yes | operator must start | `builtin:bumble` — agent key failed when Keychain ACL stale |
| Chain | **no** | **no** | — | T079 — create from `builtin:chain` |
| Tempo | **no** | **no** | — | T079 |
| Sandbox | **no** | **no** | — | T079 |
| Gate | **no** | **no** | — | T079 |
| E2E | **no** | **no** | — | T079 |

**Unblock ops:** Agents → create instance per `PLATFORM_DEV_STARTERS` → `buzz channels add-member` for each pubkey → **Start** all eight harnesses → post continuation @mention thread (see [welcome-team-chainlet-product-conversation.md](./welcome-team-chainlet-product-conversation.md#platform-team-joins-product-development-continuation--2026-09-08)).

---

## Agent MCP tools (workflows + chainlets)

Platform personas receive **baseten-chain-mcp** automatically when `chain_specialty` is set at spawn (`BUZZ_ACP_CHAIN_MCP_COMMAND` / `BASETEN_CHAIN_MCP_COMMAND`). Disable with `BUZZ_AGENT_CHAIN_MCP=0`.

| Tool | Server | Purpose |
|------|--------|---------|
| `list_chainlets` | baseten-chain-mcp | Unified registry + portfolio catalog |
| `build_chainlet_workflow` | baseten-chain-mcp | YAML for Path A dispatch workflows |
| `validate_chain_spec` / `submit_chain_job` | baseten-chain-mcp | In-session Path B chain execution |
| `create_workflow` | buzz-dev-mcp | Publish kind:30620 workflow to channel (needs `BUZZ_RELAY_URL`, `BUZZ_PRIVATE_KEY`) |
| `trigger_workflow` | buzz-dev-mcp | Fire kind:46020 trigger with optional JSON body |
| `pm_*_tool`, `scenario_*_tool` | baseten-chain-mcp | PM simulation (replay/sandbox); set `BUZZ_SCENARIO_ID` + `TOOL_BACKEND=replay` on agent |
| `submit_campaign_tool` | baseten-chain-mcp | Batch PM scenarios via Temporal `CampaignWorkflow` |

Example workflow templates: `specs/011-buzz-durable-agent-platform/examples/chainlet-*.workflow.yaml`, `scenario-pm-deliberation.workflow.yaml`.

External `buzz-mcp-server` is optional when buzz-dev-mcp is attached to the agent harness.

---

## Cross-references

| Artifact | Path |
|----------|------|
| Product conversation (seed thread) | [welcome-team-chainlet-product-conversation.md](./welcome-team-chainlet-product-conversation.md) |
| Unified agent ↔ chainlet registry | [`gpu-inference-stack/config/agent-chainlet-registry.yaml`](../../../../gpu-inference-stack/config/agent-chainlet-registry.yaml) |
| Welcome Team registry slice | [`gpu-inference-stack/config/welcome-team-chainlet-registry.yaml`](../../../../gpu-inference-stack/config/welcome-team-chainlet-registry.yaml) |
| Platform dev registry slice | [`gpu-inference-stack/config/platform-dev-agent-registry.yaml`](../../../../gpu-inference-stack/config/platform-dev-agent-registry.yaml) |
| Builtin personas (canonical prompts) | `desktop/src-tauri/src/managed_agents/personas.rs` |
| Spawn env wiring (T073) | `desktop/src-tauri/src/managed_agents/chainlet_registry.rs` |
| Durability handoff | [contracts/durability-handoff.md](../contracts/durability-handoff.md) |
| Baseten Think | [contracts/baseten-think.md](../contracts/baseten-think.md) |
| E2E closed loop | [e2e-closed-loop.md](./e2e-closed-loop.md) |

---

## Ongoing product backlog (v1)

| # | Item | Owner surface | Status |
|---|------|---------------|--------|
| 1 | Wire `BUZZ_AGENT_CHAIN_SPECIALTY` at Tauri spawn from chainlet registries | `desktop/src-tauri/src/managed_agents/chainlet_registry.rs` | done (T073) |
| 2 | `PlatformConductorWorkflow` completion predicates per specialty (semantic partial → retry or `needs_human`) | upstream `06-pipelines/agent-brain/` | blocked on T052 |
| 3 | E2E: webhook → workflow → agent wake → agent cites chain output in `#product-development` | Playwright + manifest | open |
| 4 | Per-agent specialty smoke via local shim (`BUZZ_CHAIN_LOCAL=1`) | `gpu-inference-stack/scripts/buzz-chain-openai-shim.py` | open |
| 5 | **BUZZ_CHAIN_OK** — all three specialties pass smoke with retry on induced 503 | operator evidence | open |

---

## Agent smoke test (operator @mentions)

After `./scripts/run-buzz-dev.sh` (shim + harnesses + desktop):

```bash
./scripts/ping-product-development-agents.sh --wait
```

Sends `@Fizz`, `@Honey`, and `@Pollen` pings as the human operator and optionally greps harness logs for `turn delivered`.

---

## CLI (channel creation — 2026-09-08)

```bash
# No repeated Keychain prompts — cache at ~/.config/buzz/dev-relay-identity (first source prompts once)
source experiments/01-platform/buzz/scripts/relay-env.sh
# Or from buzz repo root: source scripts/relay-env.sh

buzz channels create \
  --name product-development \
  --type stream \
  --visibility open \
  --description "Canonical product channel for Welcome Team ontology-adherent chainlets and Temporal durability."

buzz channels topic \
  --channel 28c8bf26-10fa-42e7-b658-38092562bfe1 \
  --topic "Welcome Team product: ontology chainlets + Temporal durability (spec 011)"

buzz messages send \
  --channel 28c8bf26-10fa-42e7-b658-38092562bfe1 \
  --content "…"   # opening thesis — see channel history

# Add Welcome Team agent pubkeys (2026-09-08)
for pk in \
  2d1e83ca38623e540166c06bae2ccc877529b8eaf0c02ce72ff32171394a3f3f \
  fe094f8b2f1c602d134a2095fa308d2fa2f16955215c60e5113952593a33957f \
  b657e5d491adfa12665169f5f095abfcc0fc37b23a33987a43553097738cc322; do
  buzz channels add-member --channel 28c8bf26-10fa-42e7-b658-38092562bfe1 --pubkey "$pk"
done

# After rebuilding Buzz Desktop with platform dev personas (Chain, Tempo, Sandbox, Gate, E2E):
# 1. Deploy each agent from Agents → create instance from builtin persona
# 2. Read pubkeys from managed-agents.json (do not commit pubkeys)
MANAGED_AGENTS_JSON="$HOME/Library/Application Support/xyz.block.buzz.app.dev/agents/managed-agents.json"
# Example loop (run only after agents exist on disk):
# python3 - <<'PY'
# import json, os, subprocess
# path = os.path.expanduser("~/Library/Application Support/xyz.block.buzz.app.dev/agents/managed-agents.json")
# data = json.load(open(path))
# platform_ids = {"builtin:chain", "builtin:tempo", "builtin:sandbox", "builtin:gate", "builtin:e2e"}
# channel = "28c8bf26-10fa-42e7-b658-38092562bfe1"
# for agent in data.get("agents", []):
#     if agent.get("persona_id") in platform_ids:
#         pk = agent.get("pubkey")
#         if pk:
#             subprocess.run(["buzz", "channels", "add-member", "--channel", channel, "--pubkey", pk], check=False)
# PY
# 3. Start each agent in Buzz Desktop so @mentions wake the harness
```

Do not commit or paste private keys. Use keychain hydration as shown.

---

## Acceptance (product channel)

- [x] Channel created on pathx relay with stable ID documented here
- [x] Opening message posted (human identity)
- [x] Fizz / Honey / Pollen added as channel members (`buzz channels add-member`, 2026-09-08)
- [x] Continuation thread posted with @Fizz @Honey @Pollen (event `175890c3…`)
- [ ] Platform dev agents (Chain, Tempo, Sandbox, Gate, E2E) deployed and added as members
- [ ] Agents **running** in Buzz Desktop (start Welcome Team + platform dev) to answer @mentions
- [x] Spawn env includes `BUZZ_AGENT_CHAIN_SPECIALTY` from registry (T073 — `chainlet_registry.rs`)
- [ ] At least one governed chainlet result referenced in-channel with `BUZZ_PLATFORM_JOB_ID`
