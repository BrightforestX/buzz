# Buzz wire tick 5 — Production relay wake + operator doc

**Date:** 2026-09-08  
**Slice:** S05/S06 wire follow-up  
**Prior:** `.gsd/evidence/20260908-buzz-wire-tick4.md`

## Goal

Wire real webhook → relay → desktop subscription → `start_managed_agent` with `platformJobId` / `platformTenant`. Keep mock bridge path from tick 4.

## Relay → tags

Extended `ActionSink::send_message` with optional `platform_job_id` / `platform_tenant`:

- `crates/buzz-workflow/src/action_sink.rs` — trait signature
- `crates/buzz-workflow/src/executor.rs` — reads `trigger_ctx.webhook_fields["job_id"|"tenant"]`
- `crates/buzz-relay/src/workflow_sink.rs` — emits `buzz:platform-job-id`, `buzz:platform-tenant` on kind:9

## Desktop production wake

- `platformDispatchContext.ts` — `extractPlatformDispatchContextFromEventTags`, `isRelayWorkflowDispatchEvent`, `getWorkflowMentionTargetsFromEvent`
- `usePlatformWorkflowRelayWake.ts` — live `#p` subscription for stopped managed agents; calls `useDetachedAgentStart` with platform fields
- `AppShell.tsx` — mounts hook (disabled when `__BUZZ_E2E__.mock`)

Mock path unchanged: `e2eBridge.dispatchPlatformWakeForMockWorkflow`.

## Operator documentation

- `specs/011-buzz-durable-agent-platform/docs/e2e-closed-loop.md` — Scenario B env keys + live steps (no secrets)

## CI (baseten arm64)

- `.github/workflows/_ci-rust.yml` — `baseten-arm64-smoke` on `macos-14`, `continue-on-error: true`
- Local `cargo test baseten` / `platform_job_env` still blocked (opus linker on dev machine)

## Upstream 010 T052

**Blocker unchanged:** `platformConductorWorkflow.ts` lives in `06-pipelines/agent-brain/` (010 T052 open). Not stubbed in buzz repo.

## Verification

```bash
cd desktop
pnpm build:e2e
pnpm exec playwright test platform-closed-loop --project=smoke
```

| Result | Notes |
|--------|-------|
| Playwright platform-closed-loop | **4/4 PASS** (`pnpm build:e2e` + smoke project) |

## Manifest

| Row | Status after tick 5 |
|-----|---------------------|
| `PRODUCT-B-buzz-durable-agent-platform` | **covered** (mock 4/4; production relay wired) |
| `PRODUCT-B-baseten-think` | **open** — pending arm64 CI green + operator live Think |
| `PRODUCT-B-temporal-handoff` | **open** — blocked on 010 T052 |

## Tick 6 priority

1. Operator live loop run with keys (document evidence only)
2. Promote `baseten-arm64-smoke` from `continue-on-error` once green
3. Upstream **010 T052** for temporal manifest
4. Wire-phase **complete** when live operator loop evidenced; child manifest rows may remain open
