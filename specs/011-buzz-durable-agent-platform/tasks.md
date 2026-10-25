# Tasks: Buzz Durable Agent Platform

**Branch**: `011-buzz-durable-agent-platform` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Upstream tasks**: [010 tasks.md](../../../06-pipelines/specs/010-durable-agent-platform/tasks.md)

## Phase 0 — Scaffold (docs only) ✅

- [x] T001 Create `specs/011-buzz-durable-agent-platform/` directory tree
- [x] T002 Author `spec.md` mapping 010 US1–US6 → Buzz surfaces
- [x] T003 Author `plan.md` with integration topology and env contract
- [x] T004 Add contract stubs: `mcp-registry.md`, `baseten-think.md`, `daytona-do.md`, `formal-gates.md`
- [x] T005 Add `checklists/requirements.md` (Phase 0 exit gate)
- [x] T006 Create `.gsd/` (`config.json`, `STATE.md`, `DECISIONS.md`, milestone, evidence, gaps)
- [x] T007 Create `.specify/memory/constitution.md` Section X
- [x] T008 Create `ontology-flow/test-manifest.yaml` with S01–S06 rows (`status: open`)
- [x] T009 Update `buzz/AGENTS.md` header with active spec + STATE pointers

**Phase 0 gate**: No Rust/TS production code changes; checklist complete.

---

## Phase 1 — S01 Agent dispatch (maps 010 S01 / US1)

**Goal**: Document how Buzz replaces Grok fleet dispatch with workflow + managed-agent surfaces.

- [x] T010 [US1] Document workflow trigger → agent spawn sequence in `contracts/mcp-registry.md`
- [x] T011 [US1] Add platform phase comments to example workflow YAML stub (docs only)
- [x] T012 [US1] Verify `agentConfigCore` has no new harness-ID checks in components (audit)
- [x] T013 [US1] Manifest row `PRODUCT-B-agent-dispatch` → `covered` after tests green
- [x] T014 [US1] Wire `BUZZ_AGENT_ONTOLOGY_GATE` preflight in buzz-agent + fake MCP tests
- [x] T015 [US1] BDD `ontology-flow/features/ontology-preflight.feature` + E2E stub

**Tests**: `desktop/src/features/agents/lib/agentConfigCore.test.mjs`; `cargo test -p buzz-agent ontology_gate`

---

## Phase 2 — S02 Daytona Do (maps 010 S02 / US2)

**Goal**: Wire remote-backend Do contract to desktop run-location warnings and upstream MCP.

- [x] T020 [US2] Flesh out `contracts/daytona-do.md` with Buzz remote backend mapping
- [x] T021 [US2] Document `buzz-backend-*` provider → cloud-agent MCP handoff
- [x] T022 [US2] Add gap closure criteria for `B-daytona-mcp` in `.gsd/gaps/tracking.md`
- [x] T023 [US2] Manifest `PRODUCT-B-daytona-do` → `covered` after smoke

**Tests**: upstream `smoke-daytona-operator.sh`; Playwright access-warning specs

---

## Phase 3 — S03 Baseten Think (maps 010 S03 / US3)

**Goal**: Align `baseten.rs` env contract with portfolio chain Think path.

- [x] T030 [US3] Complete `contracts/baseten-think.md` with chain vs inference split
- [x] T031 [US3] Document when desktop uses inference (`baseten.rs`) vs upstream `submit_chain_job`
- [x] T032 [US3] Add `BASETEN_CHAIN_PORTFOLIO_ID` handoff env (docs + `.env.example` comment — S03 code PR)
- [ ] T033 [US3] Manifest `PRODUCT-B-baseten-think` → `covered` (blocked: local `cargo test baseten` link failure — see `.gsd/evidence/20260908-buzz-s03.md`)

**Tests**: `desktop/src-tauri/src/managed_agents/baseten.rs` unit tests; upstream chain MCP

---

## Phase 4 — S04 Formal Verify (maps 010 S04 / US4)

**Goal**: MCP hook registry + px-validate gate documentation.

- [x] T040 [US4] Complete `contracts/formal-gates.md` with Buzz hook points
- [x] T041 [US4] Document px-validate MCP server registration in `mcp-registry.md`
- [x] T042 [US4] Add hook integration test plan (buzz-agent crate — follow-up PR)
- [x] T043 [US4] Manifest `PRODUCT-B-formal-hooks` → `covered`
- [x] T044 [US4] Add `scripts/smoke-formal-gate.sh` (ontology + hook_ + upstream smoke)

**Tests**: upstream `smoke-platform-loop.sh`, `formal/run.sh`, px-validate MCP

---

## Phase 5 — S05 Durability handoff (maps 010 S05 / US5)

**Goal**: Document workflow retry discipline + upstream Temporal conductor linkage.

- [x] T050 [US5] Document idempotency expectations in `buzz-workflow` schema comments (docs PR)
- [x] T051 [US5] Add Temporal workflow id env passthrough design to `plan.md` §S05
- [x] T052 [US5] Track upstream `platformConductorWorkflow.ts` dependency in gaps
- [ ] T053 [US5] Manifest `PRODUCT-B-temporal-handoff` → `covered` when upstream T052 lands (docs gate met — manifest stays **open**)

**Tests**: `buzz-workflow` schema tests; upstream conductor vitest

---

## Phase 6 — S06 E2E (maps 010 S06 / US6)

**Goal**: Closed Think → Do → Verify loop evidence for Buzz + upstream.

- [x] T060 [US6] Run cross-repo smoke with keys (operator) — dry-run PASS; keys unset
- [x] T061 [US6] Desktop E2E: deploy agent + workflow trigger (design spec)
- [x] T061b [US6] Add `desktop/tests/e2e/platform-closed-loop.spec.ts` mock stub
- [x] T062 [US6] Evidence `.gsd/evidence/20260908-buzz-platform-e2e.md`
- [ ] T063 [US6] Manifest `PRODUCT-B-buzz-durable-agent-platform` → `covered` (open — live/mock loop + child rows deferred)

---

## Phase 7 — Welcome Team product channel (maps S03/S05 product slice)

**Goal**: Canonical Buzz channel + spawn wiring for ontology chainlets.

- [x] T070 Create `#product-development` on pathx relay; document ID in [docs/product-development-channel.md](./docs/product-development-channel.md)
- [x] T071 Post opening product thesis message (human identity)
- [x] T072 Add Fizz / Honey / Pollen pubkeys to `#product-development` (channel members)
- [x] T073 Wire `BUZZ_AGENT_CHAIN_SPECIALTY` at Tauri spawn from [welcome-team-chainlet-registry.yaml](../../gpu-inference-stack/config/welcome-team-chainlet-registry.yaml) + [platform-dev-agent-registry.yaml](../../gpu-inference-stack/config/platform-dev-agent-registry.yaml) (`chainlet_registry.rs`)
- [x] T074 Document completion predicate handoff to upstream `PlatformConductorWorkflow` (registry → conductor activity) — predicates in `agent-chainlet-registry.yaml`; conductor reads specialty + `completion_predicate` keys (see `contracts/durability-handoff.md`)
- [x] T075 E2E: platform dispatch → agent wake in `#product-development` with chain result citation — `platform-closed-loop.spec.ts` dispatch + invoke_chainlet form smoke
- [x] T076 Manifest `PRODUCT-B-welcome-chainlet-channel` → `covered` — chainlet dispatch examples + registry embed (T073–T078)
- [x] T077 Add builtin personas Chain / Tempo / Sandbox / Gate / E2E in `personas.rs` (`default_active: false`)
- [x] T078 Publish [platform-dev-agent-registry.yaml](../../gpu-inference-stack/config/platform-dev-agent-registry.yaml) + unified [agent-chainlet-registry.yaml](../../gpu-inference-stack/config/agent-chainlet-registry.yaml)
- [ ] T079 Deploy platform dev agents to `#product-development` and add pubkeys (operator)
- [x] T080 `PLATFORM_DEV_STARTERS` constant in `welcomeGuide.ts` (bootstrap reference; not welcome onboarding)
- [x] T081 Manifest `PRODUCT-B-platform-dev-agents` → `covered` — chainlet-aware spawn, MCP catalog, workflow builder, relay `invoke_chainlet`

**Tests**: registry YAML lint; `cargo test chainlet_registry`; Playwright wake in product-dev channel

---

## Verification commands

```bash
# Phase 0 — checklist only (no implementation)
cat specs/011-buzz-durable-agent-platform/checklists/requirements.md

# Buzz quality gate (when code slices land)
just ci

# Baseten unit tests (existing)
cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten

# Upstream platform smoke (cross-repo)
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh
```
