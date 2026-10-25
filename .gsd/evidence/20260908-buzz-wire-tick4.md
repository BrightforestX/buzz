# Evidence — Buzz wire/integration tick 4 (2026-09-08)

**Milestone:** M-buzz-platform | **Prior:** [20260908-buzz-wire-tick3.md](./20260908-buzz-wire-tick3.md)

## Tasks executed

### 1. Webhook → agent wake threading (S05/S06 wire)

Thread `trigger.body.job_id` / `tenant` from mock webhook execution into @mention wake → `start_managed_agent` with `platformJobId` / `platformTenant`.

| Layer | Change |
|-------|--------|
| `desktop/src/features/workflows/lib/platformDispatchContext.ts` | `extractPlatformDispatchContext`, `expandWorkflowTriggerBodyTemplate`, `extractWorkflowMentionNames` |
| `desktop/src/features/workflows/lib/platformDispatchWake.ts` | `planPlatformDispatchWake` — first stopped @mentioned managed agent |
| `desktop/src/features/messages/ui/useMentionSendFlow.helpers.ts` | `QueuedAgentWake` optional `platformJobId`, `platformTenant` |
| `desktop/src/features/messages/ui/useDetachedAgentStart.ts` | `DetachedAgentStartOptions`; forwards platform fields to `startAgentMutateAsync` |
| `desktop/src/features/messages/ui/useMentionSendFlow.ts` | flush path passes platform fields to detached start |
| `desktop/src/testing/e2eBridge.ts` | `mock_workflow_webhook_post`, `dispatchPlatformWakeForMockWorkflow`, template expansion in mock runs, `recordMockStartManagedAgent` payload logging |

**Flow (mock bridge):** `mock_workflow_webhook_post` → workflow run with expanded `{{trigger.body.*}}` previews → `planPlatformDispatchWake` → `start_managed_agent` with platform context.

**Not wired:** production relay subscription path (real webhook → relay → desktop message → wake). Deferred to tick 5.

### 2. E2E extension (S06 wire — mock)

| Step | Result |
|------|--------|
| Add test 4 in `platform-closed-loop.spec.ts` | `mock webhook POST wakes @mentioned agent with platform job context` |
| `pnpm build:e2e` | **PASS** (after removing invalid `config.mock.relayUrl` / `communityId` accessors) |
| `pnpm exec playwright test platform-closed-loop --project=smoke` | **PASS** — **4/4** (10.1s) |

**Test 4 asserts**

- Webhook workflow with `@PlatformAgent` + `{{trigger.body.job_id}}` template
- `mock_workflow_webhook_post` with `{ job_id, tenant }`
- `start_managed_agent` payload includes `platformJobId` / `platformTenant`
- Workflow run dispatch step preview contains expanded `job_id`

### 3. Rust tests — `platform_job_env`

| Check | Result |
|-------|--------|
| `cargo test platform_job_env --manifest-path desktop/src-tauri/Cargo.toml` | **BLOCKED** — arm64 linker: undefined `opus_*` (same root cause as `cargo test baseten`) |

Unit tests exist in `metadata.rs`; require arm64-native CI or libopus fix.

### 4. Upstream 010 T052 / baseten linker — not attempted

Per scope constraint.

## Files changed (tick 4 — wire slice)

| File | Change |
|------|--------|
| `desktop/src/features/workflows/lib/platformDispatchContext.ts` | **new** — trigger body + mention parsing |
| `desktop/src/features/workflows/lib/platformDispatchWake.ts` | **new** — wake plan from workflow + agents |
| `desktop/src/features/messages/ui/useMentionSendFlow.helpers.ts` | platform fields on wake queue |
| `desktop/src/features/messages/ui/useDetachedAgentStart.ts` | platform options on detached start |
| `desktop/src/features/messages/ui/useMentionSendFlow.ts` | flush forwards platform context |
| `desktop/src/testing/e2eBridge.ts` | mock webhook POST, wake dispatch, template expansion |
| `desktop/tests/e2e/platform-closed-loop.spec.ts` | +test 4 webhook wake assert |

(Tick 3 Rust/TS spawn passthrough files unchanged functionally; listed in tick 3 evidence.)

## Manifest status

| Row | Status | Notes |
|-----|--------|-------|
| `PRODUCT-B-agent-dispatch` | covered | unchanged |
| `PRODUCT-B-buzz-durable-agent-platform` | **covered** | mock closed loop: webhook POST → wake → `platformJobId`/`platformTenant` in invoke; Playwright 4/4 |
| `PRODUCT-B-baseten-think` | **open** | opus linker (deferred child row) |
| `PRODUCT-B-temporal-handoff` | **open** | upstream 010 T052 (deferred child row) |

## Tick 5 priority

1. **Production relay wake:** wire real webhook → relay → desktop subscription → `start_managed_agent` with platform context from run metadata (not mock bridge only).
2. **Live closed loop:** operator run with platform keys; document in evidence (no secrets).
3. **arm64 CI:** `cargo test baseten` + `platform_job_env` on native runner.
4. **Upstream:** 010 T052 `platformConductorWorkflow.ts` for temporal manifest row.
