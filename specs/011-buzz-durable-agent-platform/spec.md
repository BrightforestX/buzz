# Feature Specification: Buzz Durable Agent Platform

**Feature Branch**: `011-buzz-durable-agent-platform`

**Created**: 2026-09-08

**Status**: Active — Buzz fork integration of upstream [010-durable-agent-platform](../../../06-pipelines/specs/010-durable-agent-platform/spec.md)

**Manifest**: `PRODUCT-B-buzz-durable-agent-platform`

**Upstream**: `06-pipelines/specs/010-durable-agent-platform/` (Think → Do → Verify → Durability)

**Input**: Map upstream US1–US6 onto Buzz surfaces: desktop managed agents, `buzz-agent`, `buzz-workflow`, and MCP lifecycle hooks (`MCP_HOOK_SERVERS`).

## Buzz surface map (010 → Buzz)

| Upstream US | Phase | Buzz primary surface | Secondary |
|-------------|-------|----------------------|-----------|
| US1 Grok fleet | Dispatch | `buzz-workflow` YAML triggers + relay event kinds | Desktop agent catalog (persona metadata) |
| US2 Daytona Do | Do | Managed-agent remote backends (`buzz-backend-*`) | `cloud-agent` Mastra MCP via operator tooling |
| US3 Baseten Think | Think | `desktop/src-tauri/src/managed_agents/baseten.rs` + `buzz-agent` OpenAI-compat transport | `baseten-chain-mcp` for governed chain jobs (out-of-process) |
| US4 Formal Verify | Verify | MCP hooks `_Stop` / `_PostCompact` (`docs/MCP_DRIVEN_HOOKS.md`) | px-validate MCP (`validate_proposal`) |
| US5 Temporal durability | Durability | Relay + `buzz-workflow` durable steps (design) | Upstream `agent-brain` `PlatformConductorWorkflow` |
| US6 Closed loop | Integration | Desktop agents feature + `buzz-agent` spawn env + workflow webhooks | Upstream 010 E2E evidence |

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Agent platform dispatch (maps 010 US1) (Priority: P1)

An operator configures a managed agent in Desktop (`desktop/src/features/agents/`) with harness, provider, and model. A `buzz-workflow` definition triggers the agent on channel events. Platform metadata (Think/Do/Verify/Durability phase) is documented in workflow YAML comments and agent env — not duplicated in TypeScript lookup tables per agents `AGENTS.md`.

**Why this priority**: Buzz has no Grok fleet; dispatch must flow through relay events, workflows, and managed-agent spawn.

**Independent Test**: Workflow YAML validates via `buzz-workflow` schema; agent config core projects runtime catalog fields without hardcoded harness IDs.

**Acceptance Scenarios**:

1. **Given** a workflow with `message_posted` trigger, **When** YAML is parsed, **Then** `buzz-workflow` schema accepts canonical JSON.
2. **Given** harness switch in Global Defaults, **When** provider/model changes, **Then** `onContextChange: resetDependentValues` clears dependents (agents AGENTS.md rule 4).
3. **Given** platform slice S01, **When** spec is read, **Then** phase rows map to Buzz files in `plan.md`.

---

### User Story 2 — Remote / sandbox Do stage (maps 010 US2) (Priority: P1)

A managed agent with `backend.type != "local"` runs on a provider host. Do-stage commands (tests, builds) execute in an isolated environment (Daytona via `cloud-agent` MCP) — not on the operator laptop. Desktop surfaces run-location warnings per agents AGENTS.md rule 11.

**Why this priority**: Local-only Do breaks fleet safety for shared agents.

**Independent Test**: Contract `contracts/daytona-do.md` documents MCP sequence; manifest row `PRODUCT-B-daytona-do` tracks integration status.

**Acceptance Scenarios**:

1. **Given** remote backend selected, **When** access is `anyone` or `allowlist`, **Then** `agentAccessWarning` copy names server stakes.
2. **Given** `DAYTONA_API_KEY` set and MCP available, **When** operator runs Do stage, **Then** create → exec → destroy is logged (upstream contract).
3. **Given** MCP unavailable, **When** Do runs, **Then** explicit fallback is logged — no silent host mutation.

---

### User Story 3 — Baseten Think via managed agents (maps 010 US3) (Priority: P1)

Operator selects Baseten provider in agent config. `apply_baseten_env` in `baseten.rs` translates native Baseten env into `buzz-agent` OpenAI-compatible transport (`OPENAI_COMPAT_*`). Chainlet Think (portfolio `nwxlx5wy`) remains out-of-process via upstream `baseten-chain-mcp` — Buzz does not embed chain HTTP in the desktop app.

**Why this priority**: Think must be cost-controlled; direct model inference ≠ chain specialty routing.

**Independent Test**: Rust unit tests in `baseten.rs` pin URL resolution order; manifest `PRODUCT-B-baseten-think` tracks chain integration.

**Acceptance Scenarios**:

1. **Given** `BASETEN_PROVIDER_ID`, **When** agent spawns, **Then** `BUZZ_BASETEN_NATIVE=1` and derived `OPENAI_COMPAT_BASE_URL` are set.
2. **Given** `BASETEN_MODEL_ID`, **When** no explicit model, **Then** model resolves from env chain in `resolve_baseten_model`.
3. **Given** governed chain job, **When** specialty is required, **Then** job goes through upstream MCP — not raw desktop HTTP.

---

### User Story 4 — Formal Verify via MCP hooks (maps 010 US4) (Priority: P1)

`buzz-agent` calls lifecycle hooks at `_Stop` and `_PostCompact` per `docs/MCP_DRIVEN_HOOKS.md`. Operator opts in via `MCP_HOOK_SERVERS`. px-validate MCP may object before relay writes. Hook budget and timeouts are enforced by `buzz-agent` — hooks are advisory.

**Why this priority**: Unverified agent output must not reach production relay state.

**Independent Test**: Hook contract in `contracts/formal-gates.md`; env vars documented in constitution Section X.

**Acceptance Scenarios**:

1. **Given** `MCP_HOOK_SERVERS` unset, **When** agent runs, **Then** no hook tools are invoked.
2. **Given** `_Stop` returns non-empty text, **When** budget not exhausted, **Then** agent continues turn.
3. **Given** `validate_proposal` rejects, **When** write path attempted, **Then** operation fails closed (upstream M-F1 spirit).

---

### User Story 5 — Workflow durability (maps 010 US5) (Priority: P2)

`buzz-workflow` steps that invoke agents or post relay events must leave durable retry records per Buzz AGENTS.md review-proven rule 1. Upstream Temporal (`PlatformConductorWorkflow`) owns cross-repo durability; Buzz documents handoff IDs and does not duplicate chain HTTP.

**Why this priority**: Crash mid-workflow must not orphan committed relay state.

**Independent Test**: Workflow schema documents idempotency expectations; manifest `PRODUCT-B-temporal-handoff` tracks upstream conductor linkage.

**Acceptance Scenarios**:

1. **Given** workflow step failure, **When** retry runs, **Then** generation fence prevents stale writes (AGENTS.md rule 2).
2. **Given** upstream Temporal job id, **When** documented in agent env, **Then** desktop UI can display reference (design — S05).
3. **Given** formal activity fails upstream, **When** conductor completes, **Then** Do stage is skipped (010 US5).

---

### User Story 6 — Closed Think → Do → Verify in Buzz (maps 010 US6) (Priority: P1)

Operator deploys managed `buzz-agent` with Baseten Think, optional remote Do backend, MCP formal hooks, and workflow trigger. Evidence file records which pillars participated.

**Why this priority**: Integration proof for PRODUCT-B manifest.

**Independent Test**: `.gsd/evidence/20260908-buzz-platform-phase0.md` (Phase 0 docs); live E2E deferred to S06.

**Acceptance Scenarios**:

1. **Given** Phase 0 complete, **When** checklist reviewed, **Then** all scaffold items pass with no Rust/TS production changes.
2. **Given** full env (keys + MCP + upstream conductor), **When** S06 runs, **Then** five pillars participate in documented order.
3. **Given** missing Baseten key, **When** Think runs, **Then** spawn fails visibly in desktop agent panel.

---

### Edge Cases

- **Harness catalog unknown**: Gate on runtime catalog query settling — never silently hide fields (agents AGENTS.md rule 5).
- **Effort picker**: Local-only, save-gated — no live mid-conversation effort switch (agents AGENTS.md rule 14).
- **MCP hooks vs reply guard**: `BUZZ_AGENT_REQUIRE_REPLY` shares `_Stop` budget — document in constitution X.
- **Upstream LOOP STOPPED**: Buzz 011 is sibling to 010; does not restart ontology loop.
- **Secrets**: Never commit `.env`; use `.env.example` references only.

## Requirements

### Functional Requirements

- **FR-B001**: Spec 011 MUST reference upstream 010 contracts; MUST NOT duplicate orchestration logic in Buzz repo.
- **FR-B002**: Baseten Think MUST use `managed_agents/baseten.rs` as single transport authority for desktop spawn.
- **FR-B003**: MCP hooks MUST follow `docs/MCP_DRIVEN_HOOKS.md`; allowlist via `MCP_HOOK_SERVERS` only.
- **FR-B004**: Agent config MUST obey `desktop/src/features/agents/AGENTS.md` — no rival harness capability tables in TS.
- **FR-B005**: Do stage MUST prefer isolated sandbox (Daytona MCP) over host mutation when platform keys present.
- **FR-B006**: Formal Verify MUST fail closed before relay writes when hooks or px-validate reject.
- **FR-B007**: GSD manifest rows MUST track S01–S06 in `ontology-flow/test-manifest.yaml` and `.gsd/gaps/tracking.md`.
- **FR-B008**: Constitution Section X MUST inherit upstream IX and add Buzz-specific MCP/Baseten rules.
- **FR-B009**: Welcome Team product discussions MUST use canonical channel `#product-development` (`28c8bf26-10fa-42e7-b658-38092562bfe1`); agent chain specialties MUST align with [`welcome-team-chainlet-registry.yaml`](../../gpu-inference-stack/config/welcome-team-chainlet-registry.yaml).

### Key Entities

- **Managed agent**: Desktop-deployed ACP harness with env, backend, and catalog entry.
- **Workflow definition**: YAML → canonical JSON in `buzz-workflow`.
- **Hook server**: MCP server exposing `_`-prefixed tools; filtered from LLM tool list.
- **Platform job handoff**: Upstream Temporal workflow id referenced in env/docs — not implemented in Buzz v1.

## Success Criteria

- **SC-B001**: Phase 0 checklist `checklists/requirements.md` complete with no production code changes.
- **SC-B002**: All S01–S06 manifest rows exist with `status: open` (RED/GREEN design rows).
- **SC-B003**: `.gsd/config.json` resolves upstream 010 + MCP paths from cross-repo map.
- **SC-B004**: `buzz/AGENTS.md` header points to active spec 011 and `.gsd/STATE.md`.

## Assumptions

- Phase 0 is **docs scaffold only** — no Rust/TS implementation in this slice.
- Upstream `agent-brain` owns `PlatformConductorWorkflow` implementation (010 T052).
- Buzz desktop integration with live Temporal/Baseten/Daytona is S02–S06 follow-up.
- Grok personas remain in `06-pipelines`; Buzz consumes contracts, not bot markdown.

## Related

- Plan: [plan.md](./plan.md)
- Tasks: [tasks.md](./tasks.md)
- Contracts: [contracts/](./contracts/)
- Product channel: [docs/product-development-channel.md](./docs/product-development-channel.md)
- Welcome Team chainlets: [docs/welcome-team-chainlet-product-conversation.md](./docs/welcome-team-chainlet-product-conversation.md)
- Chainlet registry: [`gpu-inference-stack/config/welcome-team-chainlet-registry.yaml`](../../gpu-inference-stack/config/welcome-team-chainlet-registry.yaml)
- Upstream: [010 spec](../../../06-pipelines/specs/010-durable-agent-platform/spec.md)
- MCP hooks: [docs/MCP_DRIVEN_HOOKS.md](../../docs/MCP_DRIVEN_HOOKS.md)
- Agents rules: [desktop/src/features/agents/AGENTS.md](../../desktop/src/features/agents/AGENTS.md)
- GSD: `.gsd/milestones/M-buzz-platform/`
