# Contract: Baseten Think (Buzz managed agents)

**Spec**: [011-buzz-durable-agent-platform](../spec.md)

**Status**: S03 complete — chain vs inference split documented; `baseten.rs` is Path A authority.

**Upstream reference**: [010 baseten-chains.md](../../../06-pipelines/specs/010-durable-agent-platform/contracts/baseten-chains.md)

**Chain registry**: [gpu-inference-stack/config/baseten-chain-ids.json](../../../gpu-inference-stack/config/baseten-chain-ids.json)

**Related**: [mcp-registry.md](./mcp-registry.md) § Think path decision tree

---

## Purpose

Define how Buzz performs **Think** (LLM reasoning) without duplicating upstream portfolio chain HTTP in desktop Tauri. Two orthogonal paths:

| Path | Name | Authority | Typical job |
|------|------|-----------|-------------|
| **A** | Direct inference | `desktop/src-tauri/src/managed_agents/baseten.rs` | Operator chat agents in Buzz desktop |
| **B** | Governed chain | `baseten-chain-mcp` (+ Temporal) | Platform specialty jobs (`verify-gate-plan`, etc.) |

**Constitution X.III**: Buzz desktop **must not** embed portfolio chain HTTP or call `submit_chain_job` from Rust/TS spawn code. Path B is operator/upstream/Grok fleet only.

---

## Chain registry (canonical IDs)

Source: `../gpu-inference-stack/config/baseten-chain-ids.json`

| Chain | ID | Role |
|-------|-----|------|
| **Portfolio (default Think)** | `nwxlx5wy` | Specialty routing — `verify-gate-plan`, `ontology-action-draft`, OpenCode/assistant-ui/midspiral specialties |
| Dynamic OSS | `lqzy7kw4` | Governed `ChainExecutionSpec` deployments |
| Legacy roadmap | `6wgorv34` | **Deprecated** for new platform jobs; still mapped for `specialty: roadmap` |

Portfolio HTTP endpoint pattern:

```http
POST https://chain-nwxlx5wy.api.baseten.co/environments/production/run_remote
Authorization: Api-Key $BASETEN_API_KEY
```

Specialty is selected via request body (`specialty`) or header `x-baseten-chain-specialty` — not by switching chain id for most portfolio specialties.

---

## Path A — Desktop inference (`baseten.rs`)

**When to use:**

- Operator selects **Baseten** provider in Global Defaults or per-agent config
- Interactive `buzz-agent` turns (channel chat, workflow @mention wake)
- Model discovery / sync inference against deployed model API
- **Not** for governed platform specialty packs requiring `ChainExecutionSpec`

**Authority file**: `desktop/src-tauri/src/managed_agents/baseten.rs`

### Base URL resolution order

1. `OPENAI_COMPAT_BASE_URL` (if already set)
2. `BASETEN_PROXY_BASE_URL`
3. `BASETEN_MODEL_APIS_BASE`
4. `https://model-{BASETEN_MODEL_ID}.api.baseten.co/v1`
5. Default `https://inference.baseten.co/v1`

### Model resolution order

Explicit spawn model → `BUZZ_AGENT_MODEL` → `BASETEN_MODEL` → `OPENAI_COMPAT_MODEL` → `BASETEN_MODEL_ID`

Example deployed model id in tests: `qelg6953` (align with gpu-inference-stack deploy notes).

### `apply_baseten_env` output (spawn)

When `provider === "baseten"`, Tauri sets:

| Env | Value |
|-----|-------|
| `BUZZ_BASETEN_NATIVE` | `1` (readiness marker) |
| `BUZZ_AGENT_PROVIDER` | `openai` |
| `OPENAI_COMPAT_BASE_URL` | resolved URL |
| `OPENAI_COMPAT_API_KEY` | `BASETEN_API_KEY` or existing compat key |
| `OPENAI_COMPAT_MODEL` | resolved model |
| `OPENAI_COMPAT_API` | `chat` |

Call sites: `runtime.rs`, `readiness.rs`, `commands/agent_models.rs`

### Rules (Path A)

1. **Single transport authority** — no TypeScript duplicate of `apply_baseten_env`
2. **Effort** — spawn-scoped via `BUZZ_ACP_EFFORT_LEVEL` / catalog; not chain output
3. **No chain portfolio HTTP** from desktop — even if operator knows `nwxlx5wy`
4. Model discovery for Databricks/Baseten follows agents AGENTS.md rule 17

---

## Path B — Governed chain (upstream MCP)

**When to use:**

- Platform specialty jobs from 010 Grok fleet / ontology-flow
- Jobs requiring **`validate_chain_spec` before spend**
- Homogeneous platform packs with `ChainExecutionSpec` JSON
- Temporal-backed chain execution with idempotency

**Package**: `../../baseten-chain-mcp/`

### Mandatory workflow (fail-closed)

```
validate_chain_spec(spec)   ← MUST pass before submit (no silent spend)
  → submit_chain_job(spec)
  → poll get_chain_job(job_id)
  → ingest result (upstream agent-brain / OMA)
```

Temporal workflow id: `chain:{tenant}:{subject}:{idempotency_key}`  
Queue: `baseten-chain`

### Environment (Path B)

| Variable | Purpose |
|----------|---------|
| `BASETEN_API_KEY` | Required |
| `BASETEN_CHAIN_PORTFOLIO_ID` | Default `nwxlx5wy` — portfolio chain for specialty routing |
| `CHAIN_EXECUTION_SPEC` | When set, agent-brain prefers MCP Path B over raw portfolio HTTP |
| `BASETEN_MODEL_ID` | Inference/deploy reference (e.g. `qelg6953`) — via spec, not desktop |
| `TEMPORAL_*` | Chain worker connectivity (upstream) |

### Portfolio specialties (subset)

From `baseten-chain-ids.json` → `specialty_to_chain_id` (all route to `nwxlx5wy` unless noted):

- `verify-gate-plan`, `ontology-action-draft`, `ontology-research-brief`
- `assistant-ui-*`, `opencode-*`, `midspiral-*` (verify stays offline per registry note)
- `deep-research-brief`, `prd-daytona-execute`
- `roadmap` → legacy `6wgorv34` (do not use for new platform jobs)

### Rules (Path B)

1. **`validate_chain_spec` required** before `submit_chain_job` on governed path
2. **No npm / formal inside Baseten handlers** — midspiral verify offline (I26)
3. **English output only** for ingest; strip SQL
4. Buzz desktop **never** calls Path B tools directly in v1 (Tauri/TS spawn code)
5. **Relay workflow `invoke_chainlet`** is permitted Path B surface: `buzz-relay` runs `baseten-chain-mcp relay_invoke` subprocess only (see `chainlet-headless-invoke.workflow.yaml`)

### Path B — Headless workflow invoke (relay executor)

Workflow action `invoke_chainlet` (kind:30620 step) runs on the **relay host**, not in Buzz desktop:

```yaml
- id: run_chainlet
  action: invoke_chainlet
  specialty: "{{trigger.body.specialty}}"
  tenant: "{{trigger.body.tenant}}"
  subject: "{{trigger.body.job_id}}"
  notify_channel: true
```

Relay env: `BASETEN_CHAIN_INVOKE_COMMAND` (default `python3 -m baseten_chain_mcp.relay_invoke`).  
Poll + optional `send_message` summary use the same Nostr workflow sink as Path A dispatch acks.

---

## Decision tree (operator)

```
Need Think for…
├─ Interactive Buzz agent chat?
│   └─ Path A: Baseten provider in desktop → baseten.rs → buzz-agent OpenAI-compat
├─ Platform specialty (verify-gate-plan, ontology-*, etc.)?
│   └─ Path B: baseten-chain-mcp validate → submit → poll
│       (Grok fleet / 06-pipelines / operator MCP — NOT desktop Rust)
└─ Legacy roadmap chain only?
    └─ Path B with specialty roadmap → chain 6wgorv34 (deprecated — migrate to portfolio)
```

---

## Handoff to agent env (S06 preview)

When upstream chain job completes, operator may pass result references into agent env (design only — not implemented S03):

- `CHAIN_JOB_ID`, `CHAIN_JOB_STATUS` — poll artifact
- Downstream Do (Daytona) triggered separately via cloud-agent MCP per [daytona-do.md](./daytona-do.md)

---

## Fail-closed rules

| Rule | Rationale |
|------|-----------|
| No desktop chain HTTP | Constitution X.III — single Baseten authority in Rust for inference only |
| `validate_chain_spec` before spend | Prevents invalid spec billing on Path B |
| Missing `BASETEN_API_KEY` → readiness fail | `BUZZ_BASETEN_NATIVE` surfaces native key errors |
| Non-Baseten provider skips `apply_baseten_env` | No accidental OpenAI-compat mutation |
| Legacy `6wgorv34` not for new jobs | Portfolio `nwxlx5wy` is default |

---

## Verification

### Desktop unit tests (S03 gate)

```bash
cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten
```

Tests in `baseten.rs`: proxy URL precedence, model-id URL, native→openai-compat mapping, non-baseten unchanged.

### Upstream (operator)

- MCP: `validate_chain_spec` with sample `ChainExecutionSpec`
- Portfolio smoke: specialty `verify-gate-plan` dry-run (requires keys)

---

## Open items (post-S03)

- [ ] Chain job → agent env handoff implementation (S06)
- [ ] agent-brain migration off legacy `6wgorv34` (upstream M-baseten-portfolio)
- [ ] Attach baseten-chain-mcp to remote agents via provider MCP sidecar (optional)
