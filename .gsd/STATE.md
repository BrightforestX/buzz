# GSD State — Buzz Durable Agent Platform

**Updated:** 2026-09-08 (wire tick 6 — wire phase closeout)
**Active milestone:** M-buzz-platform
**Phase:** **Wire phase complete** (post-wire: operator live, child manifest rows)
**Canonical spec:** `specs/011-buzz-durable-agent-platform/spec.md`
**Upstream spec:** `../../06-pipelines/specs/010-durable-agent-platform/spec.md`
**Session pointer:** Read this file + active spec before any slice work.

## Position

| Milestone | Status |
|-----------|--------|
| M-buzz-platform Phase 0 | **complete** |
| M-buzz-platform S01 | **complete** |
| M-buzz-platform S02 | **complete** |
| M-buzz-platform S03 | **docs gate met** — arm64 CI stub; promotion after 3× green on main |
| M-buzz-platform S04 | **complete** |
| M-buzz-platform S05 | **wire complete (buzz scope)** — relay wake met; Temporal blocked on **010 T052** |
| M-buzz-platform S06 | **wire complete** — PRODUCT manifest covered (mock + production relay) |

**M-buzz-platform overall:** Buzz-owned wire phase **complete** (ticks 1–6). Post-wire: live operator (keys), baseten CI promotion, upstream T052.

## Active slice

| Field | Value |
|-------|-------|
| id | post-wire-backlog |
| name | Operator live + baseten CI + upstream T052 |
| mode | human / upstream |
| surface | platform keys, arm64 CI green, `06-pipelines/agent-brain` |

## Gate results

| Gate | Status |
|------|--------|
| Phase 0 checklist | complete |
| S01 agentConfigCore | 30/30 pass |
| S02 smoke-daytona-operator | **PASS (dry-run)** |
| S02 agentAccessWarning | **8/8 pass** |
| S03 baseten-think docs | **met** |
| S03 `cargo test baseten` | **BLOCKED** local; **CI stub** macos-14 (`continue-on-error`) |
| S04 formal-gates docs | **met** |
| S04 smoke-platform-loop | **PASS** |
| S05 durability-handoff docs | **met** |
| S05 `cargo test -p buzz-workflow` | **PASS** (169 tests) |
| S06 cross-repo smokes | **PASS** / partial (cloud-agent verify:all FAIL) |
| S06 e2e design spec | **met** + Scenario B operator steps |
| S06 platform keys | **UNSET** — live loop blocked (runbook written) |
| S06 platform-closed-loop.spec.ts | **PASS** — smoke project, **4 tests** (tick 6 regression) |
| S05 production relay wake | **met** — relay tags + `usePlatformWorkflowRelayWake` |
| S05 platform env spawn (`BUZZ_PLATFORM_*`) | **mock + production** |
| Wire phase (Charter B, buzz-owned) | **complete** |
| Upstream 010 T052 | **blocked** — not stubbed in buzz |
| `just ci` | not run |

## Next action

When keys available: follow `.gsd/evidence/20260908-buzz-wire-operator-live.md`. Promote `baseten-arm64-smoke` after 3× green on main. Upstream: implement **010 T052** in `06-pipelines/agent-brain`.

## Open gaps

See `.gsd/gaps/tracking.md` (Charter B-*)

**Evidence (wire):** tick 5 `.gsd/evidence/20260908-buzz-wire-tick5.md`; tick 6 operator `.gsd/evidence/20260908-buzz-wire-operator-live.md`
