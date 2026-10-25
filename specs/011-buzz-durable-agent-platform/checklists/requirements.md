# Requirements checklist: Buzz Durable Agent Platform

**Spec**: [spec.md](../spec.md) | **Branch**: `011-buzz-durable-agent-platform` | **Phase**: 0

## Phase 0 — Docs scaffold (exit gate)

- [x] `specs/011-buzz-durable-agent-platform/spec.md` maps 010 US1–US6 to Buzz surfaces
- [x] `specs/011-buzz-durable-agent-platform/plan.md` with topology and env contract
- [x] `specs/011-buzz-durable-agent-platform/tasks.md` with Phase 0 + S01–S06 slices
- [x] Contract stubs: `mcp-registry.md`, `baseten-think.md`, `daytona-do.md`, `formal-gates.md`
- [x] `checklists/requirements.md` (this file)
- [x] `.gsd/config.json` refs local 011 + upstream 010 + MCP paths
- [x] `.gsd/STATE.md`, `.gsd/DECISIONS.md`
- [x] `.gsd/milestones/M-buzz-platform/` (ROADMAP, CONTEXT, SUMMARY)
- [x] `.gsd/evidence/20260908-buzz-platform-phase0.md`
- [x] `.gsd/gaps/tracking.md` (Charter B-* gaps)
- [x] `.specify/memory/constitution.md` Section X
- [x] `ontology-flow/test-manifest.yaml` S01–S06 rows (`status: open`)
- [x] `AGENTS.md` header updated with active spec + STATE pointer
- [x] **No Rust/TS production code changes in Phase 0**

## Pillar 1 — Agent dispatch (S01 / US1)

- [x] Workflow trigger → agent spawn documented in `mcp-registry.md`
- [x] Example workflow YAML with platform phase comments
- [x] `agentConfigCore` audit — no new harness-ID checks in components (pre-existing ui/ violations documented)
- [x] Manifest `PRODUCT-B-agent-dispatch` → `covered`

## Pillar 2 — Daytona Do (S02 / US2)

- [x] `daytona-do.md` complete with remote backend mapping
- [x] `buzz-backend-*` → cloud-agent MCP handoff documented
- [x] Gap `B-daytona-mcp` closure criteria documented (docs gate met; wire open)
- [x] Manifest `PRODUCT-B-daytona-do` → `covered`

## Pillar 3 — Baseten Think (S03 / US3)

- [x] `baseten-think.md` complete (inference vs chain split)
- [x] `baseten.rs` env contract aligned with docs
- [x] Gap `B-baseten-chain` docs gate documented (test + wire gates open)
- [ ] Manifest `PRODUCT-B-baseten-think` → `covered` (pending `cargo test baseten` in clean env)

## Pillar 4 — Formal Verify (S04 / US4)

- [x] `formal-gates.md` complete with hook + px-validate paths
- [x] Hook integration test plan in evidence (existing `hook_*` tests + H1–H4 follow-up)
- [x] Gap `B-formal-hooks` docs gate documented (wire open)
- [x] Manifest `PRODUCT-B-formal-hooks` → `covered`

## Pillar 5 — Durability (S05 / US5)

- [x] Workflow retry/idempotency documented
- [x] Upstream `PlatformConductorWorkflow` dependency tracked
- [x] Gap `B-temporal-handoff` docs gate closed (wire open — upstream T052)
- [ ] Manifest `PRODUCT-B-temporal-handoff` → `covered` (blocked: upstream 010 T052)

## Integration (S06 / US6)

- [x] Cross-repo smoke run (dry-run; keys unset — documented)
- [x] Desktop E2E design spec (`docs/e2e-closed-loop.md`)
- [x] Evidence `.gsd/evidence/20260908-buzz-platform-e2e.md`
- [ ] Manifest `PRODUCT-B-buzz-durable-agent-platform` → `covered` (open — live/mock loop + deferred child rows)

## Pre-ship gate (post Phase 0)

```bash
just ci
cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh
```

## Constitution

- [x] Section X ratified in `.specify/memory/constitution.md`
- [x] Inherits upstream IX from `06-pipelines/.specify/memory/constitution.md`
