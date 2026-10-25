# GSD Decisions — Buzz Durable Agent Platform

## 2026-09-08 — Phase 0 scaffold

**Decision**: Create spec `011-buzz-durable-agent-platform` as Buzz-local sibling integration of upstream `010-durable-agent-platform`.

**Rationale**: Upstream 010 targets Grok fleet + agent-brain conductor. Buzz fork requires explicit mapping to desktop managed agents, `buzz-agent`, workflows, and MCP hooks without duplicating orchestration logic.

**Affects**: `specs/011-*`, `.gsd/`, `ontology-flow/test-manifest.yaml`, `AGENTS.md` header.

---

## 2026-09-08 — Two-path Baseten Think

**Decision**: Desktop uses `baseten.rs` for direct inference only. Governed chain jobs (`submit_chain_job`) remain upstream/out-of-process.

**Rationale**: agents AGENTS.md rule: single transport authority in Rust. Chain HTTP in desktop would violate upstream FR-M006 and FR-B002.

**Affects**: `contracts/baseten-think.md`, gap `B-baseten-chain`.

---

## 2026-09-08 — MCP hooks opt-in

**Decision**: Platform formal Verify in Buzz starts with `MCP_HOOK_SERVERS` allowlist per `docs/MCP_DRIVEN_HOOKS.md`. Hooks off by default.

**Rationale**: Matches existing buzz-agent behavior; prevents buggy hooks from trapping agents without operator consent.

**Affects**: `contracts/formal-gates.md`, `contracts/mcp-registry.md`, Constitution X.II.

---

## 2026-09-08 — Phase 0 no code

**Decision**: Phase 0 delivers documentation scaffold only. No Rust/TS production changes.

**Rationale**: Exit gate per mission brief; implementation slices S01–S06 follow.

**Affects**: All Phase 0 tasks marked complete in `tasks.md`.

---

## Inherited from upstream (010 / Constitution IX)

- Temporal-backed flows when `TEMPORAL_*` configured (upstream agent-brain)
- `validate_chain_spec` before governed Baseten spend
- Formal verification before ontology/validated-memory writes
- Grok personas stay in `06-pipelines` — Buzz consumes contracts only

See `../../06-pipelines/.gsd/DECISIONS.md` and `../../06-pipelines/.specify/memory/constitution.md` Section IX.
