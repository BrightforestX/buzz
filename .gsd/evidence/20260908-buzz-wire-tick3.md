# Evidence — Buzz wire/integration tick 3 (2026-09-08)

**Milestone:** M-buzz-platform | **Prior:** [20260908-buzz-wire-tick2.md](./20260908-buzz-wire-tick2.md)

## Tasks executed

### 1. Platform env passthrough in Tauri spawn (S05 wire — partial)

Per `contracts/durability-handoff.md`, per-invocation env vars ride the managed-agent start path (mirrors `BUZZ_ACP_REPLAY_FLOOR`):

| Env var | Constant | Injection site |
|---------|----------|----------------|
| `BUZZ_PLATFORM_JOB_ID` | `PLATFORM_JOB_ID_ENV_VAR` | `apply_platform_job_env` → local `Command` + provider `launch.policy_env` |
| `BUZZ_PLATFORM_TENANT` | `PLATFORM_TENANT_ENV_VAR` | same |

**Rust**

| File | Change |
|------|--------|
| `desktop/src-tauri/src/managed_agents/runtime/metadata.rs` | `PlatformJobContext`, `apply_platform_job_env`, unit tests |
| `desktop/src-tauri/src/managed_agents/runtime.rs` | `spawn_agent_child` / `start_managed_agent_process` accept `Option<PlatformJobContext>` |
| `desktop/src-tauri/src/commands/agents.rs` | `start_managed_agent` args `platform_job_id`, `platform_tenant` |
| `desktop/src-tauri/src/commands/agents/provider_deploy.rs` | `apply_platform_job` → remote launch policy env |
| Restore/runtime/provider call sites | pass `None` when no platform context |

**Frontend**

| File | Change |
|------|--------|
| `desktop/src/shared/api/tauriManagedAgents.ts` | optional `platformJobId`, `platformTenant` |
| `desktop/src/features/agents/hooks.ts` | mutation forwards fields |

**Not wired this tick:** automatic population from webhook trigger → mention wake / detached agent start. Callers must pass `platformJobId` / `platformTenant` explicitly until tick 4.

**Verification**

| Check | Result |
|-------|--------|
| `cargo check --manifest-path desktop/src-tauri/Cargo.toml` | **PASS** |
| `cargo test … platform_job_env` | **BLOCKED** — arm64 opus linker (same as baseten; whole test binary fails to link) |
| Unit tests in `metadata.rs` | present (`platform_job_env_*`); run on CI arm64 or after libopus fix |

### 2. Extended closed-loop E2E (S06 wire — mock)

| Step | Result |
|------|--------|
| Extend `desktop/tests/e2e/platform-closed-loop.spec.ts` | 3 tests |
| `pnpm exec playwright test platform-closed-loop --project=smoke` | **PASS** — 3/3 |

**Playwright breakdown**

| Test | Asserts |
|------|---------|
| `mock platform dispatch workflow saves webhook trigger on agents channel` | YAML webhook trigger + send_message step |
| `managed agent start forwards platform job id and tenant` | `start_managed_agent` payload includes `platformJobId` / `platformTenant` |
| `mock webhook trigger completes dispatch ack workflow run` | 2-step workflow, UI trigger, `get_workflow_runs` completed + ack step preview |

**E2E fixes this tick:** `waitForInvokeBridge` / `gotoApp`; dismiss "Webhook ready" dialog; `Add after Step N` canvas control for second step.

### 3. Baseten / upstream 010 T052 — not attempted

| Blocker | Status |
|---------|--------|
| `cargo test baseten` / full lib test link | **BLOCKED** — undefined `opus_*` on arm64 |
| `agent-brain` 010 T052 `platformConductorWorkflow.ts` | **open** — upstream |

## Files changed (tick 3)

| File | Change |
|------|--------|
| `desktop/src-tauri/src/managed_agents/runtime/metadata.rs` | Platform job env helper + tests |
| `desktop/src-tauri/src/managed_agents/runtime.rs` | Spawn env threading |
| `desktop/src-tauri/src/commands/agents.rs` | Tauri command args |
| `desktop/src-tauri/src/commands/agents/provider_deploy.rs` | Remote policy env |
| `desktop/src-tauri/src/commands/agents/restore.rs` | `None` platform context |
| `desktop/src-tauri/src/commands/runtime_commands.rs` | `None` platform context |
| `desktop/src-tauri/src/commands/provider_access.rs` | `None` platform context |
| `desktop/src-tauri/src/personas/inbound.rs` | `None` platform context |
| `desktop/src/shared/api/tauriManagedAgents.ts` | API options |
| `desktop/src/features/agents/hooks.ts` | Hook passthrough |
| `desktop/tests/e2e/platform-closed-loop.spec.ts` | +2 tests, bridge/webhook helpers |

## Manifest status

| Row | Status | Notes |
|-----|--------|-------|
| `PRODUCT-B-agent-dispatch` | covered | unchanged |
| `PRODUCT-B-buzz-durable-agent-platform` | **open** | mock 3-test loop green; live keys + webhook→agent wake with env not proven |
| `PRODUCT-B-baseten-think` | **open** | opus linker |
| `PRODUCT-B-temporal-handoff` | **open** | spawn env partial; upstream 010 T052 |

No manifest rows closed — PRODUCT row requires full dispatch→agent wake with platform env from webhook context (or live loop).

## Tick 4 priority

1. **Webhook → wake:** thread `trigger.body.job_id` / tenant from workflow execution into `start_managed_agent` on @mention dispatch.
2. **E2E:** mock webhook POST body → assert child env contains `BUZZ_PLATFORM_*` (requires bridge hook or spawn capture).
3. **S03 test gate:** arm64 CI `cargo test baseten` + `platform_job_env` unit tests.
4. **Upstream:** 010 T052 for temporal manifest row.
