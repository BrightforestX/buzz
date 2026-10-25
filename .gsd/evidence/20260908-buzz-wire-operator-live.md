# Buzz wire — operator live loop (tick 6 closeout)

**Date:** 2026-09-08  
**Status:** **BLOCKED — platform keys unset**  
**Prior:** `.gsd/evidence/20260908-buzz-wire-tick5.md`  
**Design:** `specs/011-buzz-durable-agent-platform/docs/e2e-closed-loop.md` §Scenario B

No live cloud calls were made in this session. This document is the operator runbook + blocked checklist for when keys are available.

---

## Key status (2026-09-08)

| Variable group | Status | Blocks |
|----------------|--------|--------|
| `BASETEN_API_KEY` (+ model env) | **unset** | Think (Path A) |
| `DAYTONA_API_KEY`, `DAYTONA_ORGANIZATION_ID` | **unset** | Do (Daytona) |
| `MCP_HOOK_SERVERS` | **unset** | Verify (live px-validate / hook MCP) |
| `TEMPORAL_*` | **unset** + upstream | Durability conductor (**010 T052** not implemented) |
| Relay + desktop community | not exercised live | Dispatch (production path wired in tick 5) |

---

## Env checklist (operator shell — never commit)

Set before live loop:

```bash
# Think (required for live Baseten path)
export BASETEN_API_KEY=...          # from Baseten console
export BASETEN_MODEL=...            # or model id per contracts/baseten-think.md

# Verify (optional but recommended for full loop)
export MCP_HOOK_SERVERS=...         # px-validate or formal hook MCP URL(s)

# Do (optional — remote backend only)
export DAYTONA_API_KEY=...
export DAYTONA_ORGANIZATION_ID=...

# Durability (blocked until upstream 010 T052 lands)
# export TEMPORAL_ADDRESS=...
# export TEMPORAL_NAMESPACE=...
```

Also confirm desktop **active community relay URL** matches the webhook target relay.

---

## Smoke commands (no cloud spend unless keys set)

From **buzz root**:

```bash
# Formal + upstream scaffold (no platform keys)
bash scripts/smoke-formal-gate.sh

bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh
```

From **desktop/** (mock — no keys):

```bash
pnpm build:e2e
pnpm exec playwright test platform-closed-loop --project=smoke
```

Rust (local may fail on x86; use CI arm64 job):

```bash
cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten platform_job_env -- --test-threads=1
cargo test -p buzz-workflow
cargo test -p buzz-agent ontology_gate
```

---

## Live operator steps (when keys set)

1. Start relay + desktop (`just dev` or project equivalent); join community on target relay.
2. Deploy managed agent (Baseten provider) to channel; **stop** agent before webhook test.
3. Create/enable workflow from `examples/platform-dispatch.workflow.yaml`; copy webhook URL.
4. POST: `{"job_id":"live-op-001","tenant":"<community-id>"}`.
5. Verify channel dispatch message + agent wake (production: `usePlatformWorkflowRelayWake` → `BUZZ_PLATFORM_*`).
6. Confirm Think completes (Baseten logs / agent panel).
7. Optional: Verify hook MCP impression; Daytona sandbox; Temporal workflow after T052.

Record outcomes in a new dated evidence file; do not paste secret values.

---

## Tick 6 regression (this session)

| Command | Result |
|---------|--------|
| `bash scripts/smoke-formal-gate.sh` | **PASS** |
| `pnpm exec playwright test platform-closed-loop --project=smoke` | **4/4 PASS** |

---

## Manifest impact

| Row | Status |
|-----|--------|
| `PRODUCT-B-buzz-durable-agent-platform` | **covered** — mock + production relay; live operator deferred |
| `PRODUCT-B-baseten-think` | **open** — arm64 CI + live Think |
| `PRODUCT-B-temporal-handoff` | **open** — **010 T052** upstream blocker |

---

## Upstream blocker: 010 T052

**Owner:** `06-pipelines/agent-brain/`  
**Missing:** `src/temporal/platformConductorWorkflow.ts` (PlatformConductorWorkflow)  
**Buzz scope:** spawn env + relay durability docs only — no trivial buzz-only stub (<20 lines would not satisfy conductor contract).  
**Unblocks:** `PRODUCT-B-temporal-handoff`, live `TEMPORAL_*` verification, `platform:{tenant}:{jobId}` workflow start.

See `.gsd/gaps/tracking.md` §B-temporal-handoff and upstream `M-temporal-conductor`.
