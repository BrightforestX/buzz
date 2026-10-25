# Evidence — Buzz platform E2E rollup (S01–S06)

**Date:** 2026-09-08  
**Slice:** S06 (Phase 6 — final)  
**Spec:** `specs/011-buzz-durable-agent-platform/`  
**Tasks:** T060–T063

## T060 — Cross-repo smokes

Run from buzz root unless noted.

### smoke-platform-loop.sh

```bash
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh
```

| Result | Detail |
|--------|--------|
| **PASS** | Exit 0 (~27s) |
| Artifacts | All 010 spec files, personas, bots OK |
| Formal | `PlatformConductor.qnt`, `PlatformWorkflow.p` OK |
| Chain registry | Portfolio `nwxlx5wy` present |
| `formal/run.sh` | OK (P checker 0 bugs, Lean build OK) |

### smoke-daytona-operator.sh

```bash
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh
```

| Result | Detail |
|--------|--------|
| **PASS (dry-run)** | Exit 0 |
| Live E2E | Skipped — keys unset (see below) |
| cloud-agent launcher | `run-mastra-mcp.sh` exists |
| Contract | `daytona-sandbox.md` OK |

### cloud-agent smoke:formal

```bash
cd ../cloud-agent && npm run smoke:formal
```

| Result | Detail |
|--------|--------|
| **PARTIAL** | 19 PASS, 1 FAIL, 1 SKIP |
| FAIL | `verify:all` had failures (see cloud-agent `.gsd/evidence/20260908T055145Z-verify-all.txt`) |
| SKIP | `DAFNY2JS_PATH` unset — live POST blocked |
| Artifacts / tools | dafny, quint, dotnet present |

### Operator key status (names only — no values)

| Variable | Status |
|----------|--------|
| `DAYTONA_API_KEY` | UNSET |
| `DAYTONA_ORGANIZATION_ID` | UNSET |
| `BASETEN_API_KEY` | UNSET |
| `TEMPORAL_ADDRESS` | UNSET |
| `TEMPORAL_NAMESPACE` | UNSET |
| `TEMPORAL_API_KEY` | UNSET |
| `MCP_HOOK_SERVERS` | UNSET |

**Live Think → Do → Verify loop:** not run (no cloud keys in agent shell). Smokes are scaffold / dry-run only.

---

## T061 — Desktop E2E design spec

**Deliverable:** `specs/011-buzz-durable-agent-platform/docs/e2e-closed-loop.md`

- Scenario A (mock CI): deploy agent + webhook workflow + mock bridge
- Scenario B (live operator): key preconditions + failure visibility
- Proposed Playwright: extend `agents.spec.ts`, `workflows.spec.ts`; new `platform-closed-loop.spec.ts` (follow-up)
- Mock vs live matrix

---

## T062 — S01–S06 gate rollup

| Slice | Docs gate | Tests / smoke | Evidence | Manifest row |
|-------|-----------|---------------|----------|--------------|
| P0 | ✅ | checklist | `20260908-buzz-platform-phase0.md` | `PHASE0-buzz-scaffold` covered |
| S01 | ✅ | agentConfigCore 30/30 | `20260908-buzz-s01.md` | `PRODUCT-B-agent-dispatch` **covered** |
| S02 | ✅ | smoke-daytona dry-run; access warning 8/8 | `20260908-buzz-s02.md` | `PRODUCT-B-daytona-do` **covered** |
| S03 | ✅ | baseten tests **BLOCKED** (linker) | `20260908-buzz-s03.md` | `PRODUCT-B-baseten-think` **open** |
| S04 | ✅ | smoke-platform-loop PASS; hook plan | `20260908-buzz-s04.md` | `PRODUCT-B-formal-hooks` **covered** |
| S05 | ✅ | buzz-workflow 169 pass | `20260908-buzz-s05.md` | `PRODUCT-B-temporal-handoff` **open** |
| S06 | ✅ | smokes PASS/partial; design spec | this file | `PRODUCT-B-buzz-durable-agent-platform` **open** |

### Buzz-local test summary

| Command | Result |
|---------|--------|
| `agentConfigCore.test.mjs` | 30/30 (S01) |
| `agentAccessWarning.test.mjs` | 8/8 (S02) |
| `cargo test baseten` | BLOCKED — arm64/x86_64 opus linker |
| `cargo test -p buzz-workflow` | 169 pass (S05) |
| `cargo test hook_` | not run (documented S04) |
| `just ci` | not run |
| Live desktop Playwright platform loop | not implemented (design only) |

---

## T063 — Manifest decision

**Row:** `PRODUCT-B-buzz-durable-agent-platform`

| Criterion | Status |
|-----------|--------|
| All slice **docs** gates S01–S06 | ✅ met |
| Explicitly deferred child rows | `PRODUCT-B-baseten-think` (linker), `PRODUCT-B-temporal-handoff` (010 T052) — allowed |
| Live closed loop from desktop | ❌ not exercised |
| All platform keys present | ❌ unset |
| `just ci` | not run |
| cloud-agent `verify:all` | FAIL |

**Decision:** manifest stays **`open`**.

**Docs-gate note:** S06 design + smoke rollup complete; PRODUCT row → `covered` when (a) live or mock Playwright `platform-closed-loop` lands, (b) `cargo test baseten` passes on CI arm64, (c) optional: upstream T052 for full Temporal wire.

---

## Open blockers (honest rollup)

| ID | Blocker | Owner |
|----|---------|-------|
| B-baseten-chain | `cargo test baseten` link failure locally | Buzz CI / arm64 runner |
| B-temporal-handoff | Upstream **010 T052** `platformConductorWorkflow.ts` | 06-pipelines/agent-brain |
| B-platform-e2e | No live/mock Playwright closed loop executed | Buzz desktop follow-up |
| B-*-wire | daytona MCP inject, px-validate live, spawn env passthrough | Buzz implementation PRs |
| M-temporal-conductor | Temporal conductor not implemented | upstream |
| M-daytona-live | Live sandbox not in Buzz CI | cloud-agent + operator |

---

## Recommended next actions (operator)

1. **Upstream T052** — Implement `agent-brain/src/temporal/platformConductorWorkflow.ts`; re-run upstream vitest; then set `PRODUCT-B-temporal-handoff` → covered.
2. **CI baseten** — Run `cargo test baseten` on arm64-native runner (fix opus/arch if needed); then `PRODUCT-B-baseten-think` → covered.
3. **Live keys** — Export `BASETEN_API_KEY`, Daytona, Temporal in operator shell; run Scenario B in `docs/e2e-closed-loop.md` once.
4. **Playwright** — Add `platform-closed-loop.spec.ts` (mock bridge); wire into CI.
5. **cloud-agent** — Fix `verify:all` failures; set `DAFNY2JS_PATH` for live formal POST if needed.
6. **Buzz CI** — Schedule `smoke-platform-loop.sh` + `smoke-daytona-operator.sh` on PR/nightly.

---

## Milestone status

**M-buzz-platform:** docs-complete across S01–S06; **integration manifest open** pending deferred child rows + live/mock E2E.
