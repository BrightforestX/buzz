# Desktop E2E design — Closed Think → Do → Verify loop

**Slice:** S06 (US6) | **Spec:** [spec.md](../spec.md) | **Status:** design only (implementation follow-up PR)

Documents how Buzz desktop proves the five platform pillars in order without duplicating upstream orchestration. Live cloud spend is optional; CI defaults to mock bridge + upstream scaffold smokes.

---

## Goal

Operator (or CI) can:

1. Deploy a managed `buzz-agent` with Baseten Think env (or mock provider).
2. Enable a workflow with webhook trigger that @mentions the agent (`platform-dispatch.workflow.yaml` pattern).
3. Observe Think → Verify → Do phases with visible failure when keys or hooks reject.

**Success artifact:** `.gsd/evidence/20260908-buzz-platform-e2e.md` + manifest row `PRODUCT-B-buzz-durable-agent-platform`.

---

## Five pillars in Buzz (execution order)

| Phase | Buzz surface | Upstream / external | Mock in CI? |
|-------|--------------|---------------------|-------------|
| **Dispatch** | `buzz-workflow` webhook → relay @mention | — | ✅ mock bridge fan-out |
| **Think** | Tauri spawn → `baseten.rs` → `buzz-agent` LLM | Baseten API or chain MCP | ✅ mock OpenAI-compat |
| **Verify** | `MCP_HOOK_SERVERS` `_Stop` / px-validate | `formal/run.sh`, px-validate MCP | ✅ fake hook MCP (existing regressions) |
| **Do** | Agent MCP tools / remote backend | cloud-agent Daytona MCP | ⚠️ mock tools only in CI |
| **Durability** | `workflow_run` row + optional conductor webhook | Temporal `platform:{tenant}:{jobId}` | ✅ DB row only; no Temporal in CI |

Reference contracts: [mcp-registry.md](../contracts/mcp-registry.md), [baseten-think.md](../contracts/baseten-think.md), [daytona-do.md](../contracts/daytona-do.md), [formal-gates.md](../contracts/formal-gates.md), [durability-handoff.md](../contracts/durability-handoff.md).

---

## Scenario A — Mock closed loop (CI target)

**Preconditions**

- `installMockBridge(page)` (existing Playwright helper).
- Managed agent fixture with `buzz-agent` runtime, local backend, mock LLM responses.
- Workflow YAML pasted from `examples/platform-dispatch.workflow.yaml` (webhook trigger, @mention step).
- **Product channel (Welcome Team):** `#product-development` — `28c8bf26-10fa-42e7-b658-38092562bfe1` ([product-development-channel.md](./product-development-channel.md)). Agents deployed here for chainlet product E2E.

**Steps**

1. Navigate to Agents → deploy agent to `#agents` channel (reuse `agents.spec.ts` managed-agent helpers).
2. Open Workflows → create workflow from example YAML (`workflows.spec.ts` create helpers).
3. Enable workflow; copy webhook URL (UI or relay API fixture).
4. POST webhook body: `{"job_id":"e2e-mock-001","tenant":"test-community"}` (mock bridge simulates relay).
5. Assert channel receives dispatch ack message (thread reply from `ack_dispatch` step).
6. Assert agent panel shows turn started (Think mock).
7. Optional: configure fake `_Stop` hook MCP — assert turn blocked when hook objects.

**Playwright specs to extend (not new files required for v1 design)**

| Spec file | Reuse | New test name (proposed) |
|-----------|-------|-------------------------|
| `desktop/tests/e2e/agents.spec.ts` | managed agent deploy fixtures | `platform agent deploys with baseten env placeholders` |
| `desktop/tests/e2e/workflows.spec.ts` | create/edit YAML workflow | `platform dispatch workflow webhook trigger saves` |
| `desktop/tests/e2e/onboarding-agent-defaults.spec.ts` | agent defaults | (no change — S01 covered) |
| `desktop/tests/e2e/agent-access-warning.spec.ts` | remote backend warning | `remote backend shows Do handoff warning` (S02 covered) |
| **`desktop/tests/e2e/platform-closed-loop.spec.ts`** | **new file (follow-up)** | `mock platform dispatch wakes deployed agent` |

**Rust / unit (no Playwright)**

| Test | Command |
|------|---------|
| baseten transport | `cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten` |
| hook regressions | `cargo test hook_ -p buzz-agent` |
| workflow schema | `cargo test -p buzz-workflow` |

---

## Scenario B — Live closed loop (operator only)

**Preconditions** — set in operator shell only (never commit secrets). Relay and desktop must be running against the **same** community relay URL.

### Environment keys

| Variable | Required for | Notes |
|----------|--------------|-------|
| `BASETEN_API_KEY` | Think (Path A) | Baseten inference; see `contracts/baseten-think.md` |
| `BASETEN_MODEL` / model env | Think | Model id for `baseten.rs` transport |
| `DAYTONA_API_KEY`, `DAYTONA_ORGANIZATION_ID` | Do via Daytona | Remote backend only |
| `MCP_HOOK_SERVERS` | Verify | px-validate or formal hook MCP URL(s) |
| `TEMPORAL_*` | Durability conductor | Blocked until upstream **010 T052** |
| Relay URL + desktop community | Dispatch | Desktop `activeCommunity.relayUrl` must match webhook target |

Platform job correlation (tick 5 production path):

| Source | Desktop / agent |
|--------|-----------------|
| Webhook body `job_id`, `tenant` | Relay `TriggerContext.webhook_fields` |
| Relay kind:9 tags | `buzz:platform-job-id`, `buzz:platform-tenant` |
| Live subscription | `usePlatformWorkflowRelayWake` → `start_managed_agent` |
| Agent process env | `BUZZ_PLATFORM_JOB_ID`, `BUZZ_PLATFORM_TENANT` |

Mock CI uses `e2eBridge.dispatchPlatformWakeForMockWorkflow` instead of live relay tags.

**Operator evidence (live):** `.gsd/evidence/20260908-buzz-wire-operator-live.md` — keys unset as of 2026-09-08; runbook only, no live cloud calls.

### Operator steps (live)

1. Start relay (`just dev` or project equivalent) and desktop dev app; join/create community on that relay.
2. Deploy managed agent with Baseten provider to a channel; ensure agent is **stopped** before webhook test (production wake targets stopped agents).
3. Create workflow from `examples/platform-dispatch.workflow.yaml`; enable webhook trigger; copy webhook URL from UI.
4. POST webhook JSON, e.g. `{"job_id":"live-op-001","tenant":"<community-id>"}` (use stable ids).
5. Confirm channel receives workflow dispatch message with `@Agent` mention.
6. Confirm agent starts (panel shows turn / logs); verify invoke payload includes `platformJobId` / `platformTenant` if using mock bridge inspector, or agent env in logs.
7. Optional: attach Verify hook MCP; confirm hook runs before turn completes.
8. Optional: remote backend + Daytona keys for Do phase.
9. Optional: when **010 T052** lands, confirm Temporal workflow `platform:{tenant}:{jobId}` in agent-brain logs.

**Failure modes (must be visible)**

- Missing `BASETEN_API_KEY` → spawn error in agent panel (US6 scenario 3).
- Hook rejection → turn does not complete; no silent relay write.
- Missing Daytona keys → Do skipped or warning banner (S02 `agent-access-warning`).

---

## Mock vs live matrix

| Check | Mock (CI) | Live (operator) |
|-------|-----------|-----------------|
| Workflow webhook → mention | mock bridge event | real relay POST |
| LLM Think | stub OpenAI-compat | Baseten API |
| MCP `_Stop` | fake MCP server in test | px-validate / custom hook |
| Daytona Do | skip or tool mock | cloud-agent MCP + sandbox |
| Temporal durability | document job_id only | agent-brain worker |
| Upstream smokes | always run (no spend) | same + optional live MCP |

---

## Upstream smoke integration (S06 T060)

Run from buzz root (document in evidence):

```bash
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh
cd ../cloud-agent && npm run smoke:formal   # if node_modules present
```

These validate cross-repo contracts and formal models — not full desktop UI.

---

## Implementation follow-up (out of scope for docs S06)

1. ~~Add `platform-closed-loop.spec.ts` with mock bridge end-to-end.~~ **Done (tick 4).**
2. ~~Wire `BUZZ_PLATFORM_JOB_ID` into Tauri spawn when webhook context available.~~ **Mock + production relay (tick 5).**
3. CI matrix: arm64 runner for `cargo test baseten`; scheduled upstream smokes. **Stub job added tick 5** — see `.gsd/gaps/tracking.md`.
4. Block PRODUCT manifest `covered` until live loop or explicit waiver — mock covered; live operator loop open.

---

## Traceability

| US6 acceptance | Design coverage |
|----------------|-----------------|
| Phase 0 scaffold complete | Phase 0 evidence |
| Five pillars in documented order | Table above + contracts |
| Missing Baseten key fails visibly | Scenario B failure modes; mock uses env guard tests in `baseten.rs` |
| Welcome Team product channel documented | `#product-development` ID in [product-development-channel.md](./product-development-channel.md); spawn uses [welcome-team-chainlet-registry.yaml](../../../../gpu-inference-stack/config/welcome-team-chainlet-registry.yaml) |
