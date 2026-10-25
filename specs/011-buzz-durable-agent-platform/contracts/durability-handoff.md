# Durability handoff — Buzz workflow vs upstream Temporal

**Slice:** S05 (US5) | **Upstream:** [010 plan §PlatformConductorWorkflow](../../../06-pipelines/specs/010-durable-agent-platform/plan.md#platformconductorworkflow-design)

Buzz owns **relay-local** workflow durability (`buzz-workflow` run rows). Upstream **agent-brain** owns cross-repo platform durability via Temporal (`PlatformConductorWorkflow`, 010 T052). Buzz documents handoff IDs and env passthrough; it does **not** duplicate chain HTTP or conductor activities.

---

## Responsibility split

| Layer | Owner | Durable artifact | Retry model |
|-------|-------|------------------|-------------|
| Workflow trigger + steps | Buzz relay | `workflow_run` row (Postgres) | See §Buzz engine semantics |
| Think → Verify → Do platform loop | agent-brain | Temporal workflow `platform:{tenant}:{jobId}` | Temporal activity retry + workflow idempotency |
| Chain execution | baseten-chain-mcp | `chain:{tenant}:{subject}:{idempotencyKey}` | Temporal queue `baseten-chain` |

**Invariant M-T1:** Baseten submit for a platform job must follow a Temporal workflow start (Quint `PlatformConductor.qnt`). Buzz surfaces `job_id` / workflow id in env and webhook context; conductor implementation is upstream.

---

## Platform job idempotency (operator contract)

### Stable identifiers

| Field | Source | Rule |
|-------|--------|------|
| `job_id` | Webhook JSON body → `trigger.body.job_id` | **Required** for platform dispatch; must be stable across retries of the *same logical job* |
| `tenant` | Relay community id or operator-defined slug | Used in Temporal id: `platform:{tenant}:{jobId}` |
| Temporal workflow id | agent-brain | `platform:${tenant}:${jobId}` — duplicate start with same id is idempotent at Temporal |

### Buzz webhook behavior

- Each successful webhook POST creates a **new** `workflow_run` (no built-in dedup on `job_id`).
- Operators who POST the same webhook twice without coordination get **two runs** unless they dedupe at the client or use schedule-claim patterns.
- **Recommended:** one webhook per logical platform job; pass the same `job_id` into agent spawn env and optional `notify_upstream` body so downstream systems can dedupe.

### Agent / desktop handoff

When Tauri spawns a managed agent for a platform job (future wire), pass:

| Env var | Example | Purpose |
|---------|---------|---------|
| `BUZZ_PLATFORM_JOB_ID` | `job-20260908-abc` | Correlates agent session with platform job |
| `BUZZ_PLATFORM_TENANT` | `community-uuid-or-slug` | Tenant segment for Temporal id |
| `TEMPORAL_WORKFLOW_ID` | `platform:acme:job-20260908-abc` | Read-only correlation for UI/logs (set by operator or conductor callback) |

Secrets (`TEMPORAL_API_KEY`, etc.) stay on agent-brain workers — not injected into desktop spawn in v1.

---

## Buzz-workflow engine semantics (retry / fail-closed)

Reference implementation: `crates/buzz-workflow/` (`lib.rs`, `executor.rs`, `schema.rs`).

### Run lifecycle

1. **Trigger** — event, webhook, or scheduled tick creates `workflow_run` (`create_workflow_run`).
2. **Execute** — steps run sequentially in-process; trace appended per step.
3. **Finalize** — `finalize_run` sets status **Completed** or **Failed** (single mapping point).

There is **no automatic retry** of a failed step inside one run. A failed run stays **Failed** until an operator starts a new run (new webhook, new event, or next schedule tick).

### Step-level behavior

| Behavior | Semantics |
|----------|-----------|
| Step error | Run → **Failed** at failing step index; later steps not executed |
| `if:` false | Step **skipped** (not failure) |
| Approval gate | **Failed** with `approval_not_supported` (WF-08 not implemented) |
| Hook timeout (agent) | Fail-open for liveness — separate from workflow engine |

### Scheduled (cron / interval) idempotency

- `claim_scheduled_workflow_fire(community_id, workflow_id, scheduled_for)` ensures **one fire per scheduled instant** across relay pods.
- `scheduled_for` is computed deterministically from cron expression or interval bucket — process bounce cannot double-fire the same tick.
- This is **not** the same as platform `job_id` dedup; it applies only to schedule triggers.

### Webhook / event triggers

- Each qualifying trigger event → new run row.
- Trigger context JSON (including `trigger.body`) is stored on the run for template expansion (`{{trigger.body.job_id}}`).

### Platform jobs — idempotency expectations

| Scenario | Expected behavior |
|----------|-------------------|
| Operator retries failed platform job | New webhook with **same** `job_id`; upstream Temporal start must use same `platform:{tenant}:{jobId}` so conductor dedupes; Buzz may create a second run row (document in ops runbook) |
| Duplicate webhook (network retry) | Two Buzz runs unless client dedupes; conductor should still idempotent-start on Temporal id |
| Workflow step `call_webhook` to conductor | Best-effort POST; failure fails the Buzz run — operator re-triggers |
| Agent Verify failure | Agent session ends; platform conductor marks job failed (when T052 implemented) — no silent retry of invalid writes |

Aligns with Buzz AGENTS.md review-proven rule 1: caught failures leave a durable record or propagate.

---

## Optional upstream notify step

Example: `specs/011-buzz-durable-agent-platform/examples/platform-dispatch.workflow.yaml` step `notify_upstream`.

```json
{"job_id":"<stable>","phase":"dispatch","source":"buzz-workflow"}
```

When `platformConductorWorkflow.ts` exists, conductor HTTP handler should accept this and start or signal `platform:{tenant}:{jobId}`.

---

## Verification

| Check | Command / artifact |
|-------|-------------------|
| Schema + engine unit tests | `cargo test -p buzz-workflow` |
| Example YAML parses | `buzz-workflow` `parse_yaml` (schema tests) |
| Upstream conductor | `agent-brain/src/temporal/platformConductorWorkflow.ts` + vitest (010 T052) |
| Formal model | `formal/PlatformConductor.qnt` (smoke-platform-loop) |

---

## Code anchors

| Topic | Path |
|-------|------|
| Run finalize | `crates/buzz-workflow/src/lib.rs` — `finalize_run` |
| Scheduled claim | `crates/buzz-workflow/src/lib.rs` — `claim_scheduled_workflow_fire` |
| Step execution | `crates/buzz-workflow/src/executor.rs` |
| Example workflow | `specs/011-buzz-durable-agent-platform/examples/platform-dispatch.workflow.yaml` |
| Env passthrough design | `specs/011-buzz-durable-agent-platform/plan.md` §S05 |
| Upstream conductor design | `../../06-pipelines/specs/010-durable-agent-platform/plan.md` |

---

## Gap / manifest

- **Docs gate (S05):** this file + plan §S05 + example YAML comments.
- **Wire gate:** upstream **010 T052** `platformConductorWorkflow.ts` + Buzz env passthrough in spawn path.
- Manifest `PRODUCT-B-temporal-handoff` → **covered** only when upstream T052 lands; otherwise **open** with docs-gate note in `.gsd/evidence/20260908-buzz-s05.md`.
