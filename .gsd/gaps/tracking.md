# Charter gap tracking — Buzz durable agent platform

Open until closed in code + manifest row `status: covered`. Synced to `ontology-flow/test-manifest.yaml`.

**Charter**: B (Buzz platform integration — sibling to upstream Charter M in 06-pipelines)

## Phase 0 (closed)

Closed (`B-phase0-scaffold` `covered`): spec 011, GSD, constitution X, contract stubs, test manifest rows, Phase 0 evidence.

## Closed gaps (S01)

| ID | Closed | Evidence |
|----|--------|----------|
| B-agent-dispatch | 2026-09-08 | `.gsd/evidence/20260908-buzz-s01.md`, manifest `PRODUCT-B-agent-dispatch` covered |

### S01 wire — ontology preflight (tick 1)

| Criterion | Status |
|-----------|--------|
| `BUZZ_AGENT_ONTOLOGY_GATE=1` session/new preflight | ✅ |
| fake MCP `validate_proposal` + integration tests | ✅ 7 pass |
| BDD `ontology-preflight.feature` | ✅ |
| E2E stub `ontology-preflight.spec.ts` | ✅ added — Playwright pending build |
| Desktop spawn passes gate env from Tauri | partial — ontology gate + platform job env on `start_managed_agent` (tick 3–4) |

Evidence: `.gsd/evidence/20260908-buzz-wire-tick1.md`

## B-daytona-mcp closure criteria

Gap ID: **B-daytona-mcp** — Remote backend Do ↔ cloud-agent Daytona MCP integration.

### S02 docs gate — **met 2026-09-08**

| Criterion | Status |
|-----------|--------|
| `contracts/daytona-do.md` complete (mapping, sequence, fail-closed) | ✅ |
| `contracts/mcp-registry.md` § buzz-backend handoff | ✅ |
| Upstream `smoke-daytona-operator.sh` dry-run PASS | ✅ |
| Desktop `agentAccessWarning.test.mjs` pass | ✅ 8/8 |
| Manifest `PRODUCT-B-daytona-do` → covered | ✅ |

Evidence: `.gsd/evidence/20260908-buzz-s02.md`

### Full wire gate — **open** (post-S02 implementation)

| Criterion | Status |
|-----------|--------|
| `buzz-backend-*` deploy injects cloud-agent MCP endpoint env | open |
| Remote agent MCP config documented in operator runbook + tested once | open |
| Buzz CI nightly runs `smoke-daytona-operator.sh` | open |
| Live Daytona create/destroy exercised with keys (operator) | open |
| Playwright `agent-access-warning.spec.ts` in CI matrix | open |

Until full wire gate passes, upstream dependency **M-daytona-live** remains open.

## B-baseten-chain closure criteria

Gap ID: **B-baseten-chain** — Desktop inference (Path A) vs governed chain handoff (Path B).

### S03 docs gate — **met 2026-09-08**

| Criterion | Status |
|-----------|--------|
| `contracts/baseten-think.md` complete (Path A vs B, portfolio `nwxlx5wy`, validate before spend) | ✅ |
| `contracts/mcp-registry.md` § Think path decision tree | ✅ |
| `plan.md` + `.env.example` env contract (`BASETEN_CHAIN_PORTFOLIO_ID`, `CHAIN_EXECUTION_SPEC`) | ✅ |
| `baseten.rs` unit tests exist (4 cases) | ✅ (source) |

Evidence: `.gsd/evidence/20260908-buzz-s03.md`

### Test gate — **open**

| Criterion | Status |
|-----------|--------|
| `cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten` pass | open — local link failure (x86_64 opus vs arm64 rustc) |
| Manifest `PRODUCT-B-baseten-think` → covered | open |

### Full wire gate — **open** (post-S03 implementation)

| Criterion | Status |
|-----------|--------|
| Platform jobs pass `CHAIN_EXECUTION_SPEC` + `BASETEN_CHAIN_PORTFOLIO_ID` via agent-brain/Grok (not desktop spawn) | open |
| `validate_chain_spec` exercised once in operator smoke with keys | open |
| Upstream agent-brain defaults to portfolio `nwxlx5wy` (not legacy `6wgorv34`) | open — **M-baseten-portfolio** |
| Buzz CI runs `cargo test baseten` on arm64-native runner | **stub** — `.github/workflows/_ci-rust.yml` `baseten-arm64-smoke` (`continue-on-error: true`). **Promotion:** remove `continue-on-error` after **3 consecutive green** runs on `main`; then set `PRODUCT-B-baseten-think` → covered if operator live Think also evidenced. |

Until test + wire gates pass, manifest `PRODUCT-B-baseten-think` remains `open`.

## B-formal-hooks closure criteria

Gap ID: **B-formal-hooks** — MCP lifecycle hooks + px-validate Verify integration.

### S04 docs gate — **met 2026-09-08**

| Criterion | Status |
|-----------|--------|
| `contracts/formal-gates.md` complete (hooks, px-validate, M-T1/M-T2/M-B1/M-F1) | ✅ |
| `contracts/mcp-registry.md` § px-validate registration + `validate_proposal` flow | ✅ |
| Hook test plan in `.gsd/evidence/20260908-buzz-s04.md` | ✅ |
| Existing `hook_*` regression tests documented (`regressions.rs`) | ✅ |
| Upstream `smoke-platform-loop.sh` PASS | ✅ |
| Manifest `PRODUCT-B-formal-hooks` → covered | ✅ |

Evidence: `.gsd/evidence/20260908-buzz-s04.md`

### Wire gate — **open** (post-S04 implementation)

| Criterion | Status |
|-----------|--------|
| `cargo test hook_` in Buzz CI | open |
| `scripts/smoke-formal-gate.sh` in Buzz repo | ✅ tick 1 |
| px-validate mock integration tests H1–H4 (evidence plan) | open |
| Example px-validate `_Stop` wrapper MCP server | open |
| Live px-validate MCP exercised once with operator keys | open |
| `_FormalGate` hook point in buzz-agent (optional) | open |
| Buzz CI runs `smoke-platform-loop.sh` on schedule | open |

Until wire gate passes, **B-formal-hooks-wire** tracks remaining implementation.

## B-temporal-handoff closure criteria

Gap ID: **B-temporal-handoff** — Buzz workflow durability docs + upstream Temporal conductor linkage.

### S05 docs gate — **met 2026-09-08**

| Criterion | Status |
|-----------|--------|
| `contracts/durability-handoff.md` complete (idempotency, retry, engine semantics) | ✅ |
| `examples/platform-dispatch.workflow.yaml` idempotency/retry comment block | ✅ |
| `plan.md` §S05 Temporal env passthrough (`platform:{tenant}:{jobId}`) | ✅ |
| Upstream `PlatformConductorWorkflow` design referenced (010 plan) | ✅ |
| `cargo test -p buzz-workflow` pass | ✅ 169 pass |

Evidence: `.gsd/evidence/20260908-buzz-s05.md`, tick 3 spawn wire `.gsd/evidence/20260908-buzz-wire-tick3.md`

### Wire gate — **open** (blocked on upstream 010 T052)

| Criterion | Status |
|-----------|--------|
| `agent-brain/src/temporal/platformConductorWorkflow.ts` implemented | **blocked** — upstream **010 T052** (not buzz-owned; no buzz stub) |
| Buzz Tauri spawn injects `BUZZ_PLATFORM_JOB_ID` / `BUZZ_PLATFORM_TENANT` | **production relay met** — relay tags + `usePlatformWorkflowRelayWake` (tick 5); mock bridge unchanged |
| Live Temporal start with `platform:{tenant}:{jobId}` exercised once | open |
| Manifest `PRODUCT-B-temporal-handoff` → covered | open (conditional on T052) |

Until wire gate passes, upstream dependency **M-temporal-conductor** remains the live-durability blocker.

## B-platform-e2e closure criteria

Gap ID: **B-platform-e2e** — Closed Think → Do → Verify loop from Buzz desktop + cross-repo smokes.

### S06 docs gate — **met 2026-09-08**

| Criterion | Status |
|-----------|--------|
| Cross-repo smokes run and documented | ✅ platform-loop PASS; daytona dry-run PASS; cloud-agent formal partial |
| `docs/e2e-closed-loop.md` design spec | ✅ |
| Evidence rollup S01–S06 | ✅ this milestone |
| Key status documented (no secrets) | ✅ all platform keys UNSET in agent shell |

Evidence: `.gsd/evidence/20260908-buzz-platform-e2e.md`

### Wire gate — **mock met 2026-09-08** (live open)

| Criterion | Status |
|-----------|--------|
| Live desktop platform loop with keys | **blocked** — keys unset; runbook `.gsd/evidence/20260908-buzz-wire-operator-live.md` |
| Playwright `platform-closed-loop.spec.ts` (mock or live) | smoke **PASS** — **4 tests** (YAML, invoke payload, trigger+ack, webhook POST→wake) |
| Manifest `PRODUCT-B-buzz-durable-agent-platform` → covered | **covered** |
| Child rows baseten + temporal | open (explicitly deferred) |
| Production relay webhook → wake (non-mock) | **met** — tick 5 relay tags + desktop subscription |

Evidence: `.gsd/evidence/20260908-buzz-wire-operator-live.md`

**Wire phase (Charter B, buzz-owned):** **complete** as of tick 6. Post-wire backlog: live operator loop (keys), `PRODUCT-B-baseten-think` (arm64 CI green), `PRODUCT-B-temporal-handoff` (010 T052).

## Open gaps

| ID | Gap | File anchor | Manifest |
|----|-----|-------------|----------|
| B-daytona-mcp-wire | Provider MCP inject + live E2E not implemented | `crates/buzz-backend-kubernetes/`, agent MCP config | (sub-criterion of B-daytona-mcp) |
| B-baseten-chain-wire | Governed chain env handoff not wired in desktop spawn (by design) | `contracts/baseten-think.md`, agent-brain | (sub-criterion of B-baseten-chain) |
| B-baseten-chain | Docs gate met; test + wire open | `contracts/baseten-think.md`, `baseten.rs` | `PRODUCT-B-baseten-think` |
| B-formal-hooks-wire | px-validate live MCP + H1–H4 tests not implemented | `contracts/formal-gates.md`, `regressions.rs` | (sub-criterion of B-formal-hooks) |
| B-formal-hooks | Docs gate met; wire open | `contracts/formal-gates.md`, `docs/MCP_DRIVEN_HOOKS.md` | `PRODUCT-B-formal-hooks` (covered) |
| B-temporal-handoff | Docs gate met; wire blocked on upstream 010 T052 | `contracts/durability-handoff.md`, `plan.md` §S05 | `PRODUCT-B-temporal-handoff` (open) |
| B-platform-e2e | Wire complete (mock + relay); live operator blocked on keys | `docs/e2e-closed-loop.md`, operator-live evidence | `PRODUCT-B-buzz-durable-agent-platform` (**covered**) |

## Upstream dependencies (not Buzz-owned)

| ID | Gap | Owner repo |
|----|-----|------------|
| M-baseten-portfolio | agent-brain defaults legacy chain `6wgorv34` | 06-pipelines/agent-brain |
| M-temporal-conductor | `PlatformConductorWorkflow` not implemented (**010 T052 open**) | 06-pipelines/agent-brain |
| M-daytona-live | Daytona MCP not in Buzz CI | cloud-agent |

See `../../06-pipelines/.gsd/gaps/tracking.md` Charter M.

## Notes

- Buzz does not restart upstream ontology LOOP (STOPPED).
- Secrets never committed — env templates only in docs.
- Gap IDs prefixed `B-` for Buzz charter; upstream `M-*` gaps tracked in 06-pipelines.
- S02 closed the **docs gate** for B-daytona-mcp; **B-daytona-mcp-wire** tracks remaining implementation.
