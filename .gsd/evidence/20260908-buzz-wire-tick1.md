# Evidence — Buzz wire/integration tick 1 (2026-09-08)

**Milestone:** M-buzz-platform | **Phase:** wire follow-up (post docs-complete)

## Implemented

### S01 — Ontology preflight gate (`buzz-agent`)

| Artifact | Path |
|----------|------|
| Gate module | `crates/buzz-agent/src/ontology_gate.rs` |
| Config env | `BUZZ_AGENT_ONTOLOGY_GATE`, `BUZZ_AGENT_ONTOLOGY_PREFLIGHT_CLASS`, `BUZZ_AGENT_ONTOLOGY_GATE_TIMEOUT_MS` |
| Session hook | `session/new` → `run_preflight` after MCP spawn (`lib.rs`) |
| Fake MCP tool | `tests/bin/fake_mcp.rs` — `FAKE_MCP_VALIDATE_PROPOSAL`, `FAKE_MCP_VALIDATE_FAIL` |
| Integration tests | `crates/buzz-agent/tests/ontology_gate.rs` (4 cases) |
| BDD feature | `ontology-flow/features/ontology-preflight.feature` |
| E2E stub | `desktop/tests/e2e/ontology-preflight.spec.ts` |

**Behavior:** When `BUZZ_AGENT_ONTOLOGY_GATE=1`, first MCP server exposing `validate_proposal` is called with `{ data: {}, class_name, check_registry: false }`. Missing tool, timeout, MCP error, `isError`, or `ok: false` → session rejected (fail-closed).

**Fix:** `borrow_and_update()` on cancel receiver before `mcp.call` — avoids spurious `Cancelled` from tokio `watch::changed()` initial wakeup.

### S04 — Formal smoke script

| Artifact | Path |
|----------|------|
| Buzz smoke | `scripts/smoke-formal-gate.sh` |

Runs: `cargo test -p buzz-agent ontology_gate`, `cargo test -p buzz-agent hook_`, upstream `smoke-platform-loop.sh`.

### S06 — Mock closed-loop E2E stub

| Artifact | Path |
|----------|------|
| Playwright spec | `desktop/tests/e2e/platform-closed-loop.spec.ts` |

Creates webhook workflow on `#agents` channel via mock bridge; asserts YAML has `trigger.on: webhook` and `send_message` step.

## Test results

| Command | Result |
|---------|--------|
| `cargo test -p buzz-agent ontology_gate` | **PASS** — 3 unit + 4 integration |
| `bash scripts/smoke-formal-gate.sh` | **PASS** |
| `pnpm exec playwright test … ontology-preflight platform-closed-loop` | **NOT RUN** — webServer timeout (needs `pnpm build:e2e` first) |

## Manifest status (unchanged — open rows stay open)

| Row | Status | Notes |
|-----|--------|-------|
| `PRODUCT-B-agent-dispatch` | covered | S01 docs; wire adds rust_test ref |
| `PRODUCT-B-buzz-durable-agent-platform` | **open** | stub spec added; full loop deferred |
| `PRODUCT-B-baseten-think` | open | arm64 baseten tests |
| `PRODUCT-B-temporal-handoff` | open | upstream 010 T052 |

## Next (tick 2)

1. `pnpm build:e2e` + run `platform-closed-loop.spec.ts` and `ontology-preflight.spec.ts` in CI matrix.
2. Wire `BUZZ_PLATFORM_JOB_ID` into Tauri spawn when webhook context available.
3. arm64 `cargo test baseten`; upstream Temporal T052 for durability manifest.
