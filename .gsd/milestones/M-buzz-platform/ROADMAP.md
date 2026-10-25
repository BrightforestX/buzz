# M-buzz-platform ROADMAP — Buzz Durable Agent Platform

**Spec:** [specs/011-buzz-durable-agent-platform/spec.md](../../specs/011-buzz-durable-agent-platform/spec.md)

**Upstream:** [010-durable-agent-platform](../../../06-pipelines/specs/010-durable-agent-platform/spec.md)

## Slices

| Slice | Upstream US | Buzz deliverable | Unit / E2E test | Playwright / Rust | Status |
|-------|-------------|------------------|-----------------|-------------------|--------|
| S01 | US1 | Workflow + agent dispatch docs | `agentConfigCore.test.mjs` | — | **done** |
| S02 | US2 | `daytona-do.md` + remote run-location | `agentAccessWarning.test.mjs` | `agent-access-warning.spec.ts` | **done** |
| S03 | US3 | `baseten-think.md` + env contract | `baseten.rs` tests | `cargo test baseten` | **done (docs)** — arm64 CI stub; promote after 3× green |
| S04 | US4 | `formal-gates.md` + hook registry | hook regression tests | `smoke-platform-loop.sh` | **done** |
| S05 | US5 | Workflow durability + Temporal handoff | `buzz-workflow` schema tests | `cargo test -p buzz-workflow` | **wire complete (buzz)** — Temporal blocked **010 T052** |
| S06 | US6 | E2E evidence + manifest covered | upstream smoke + desktop E2E | `platform-closed-loop.spec.ts` **PASS** (4 mock) | **wire complete** — production relay + operator runbook |
| **P0** | — | Docs scaffold (Phase 0) | checklist | — | **done** |

## Buzz boundary map

```
buzz/ (.gsd primary for fork)
├── specs/011-buzz-durable-agent-platform/
├── desktop/src/features/agents/     ← config UI + AGENTS.md rules
├── desktop/src-tauri/managed_agents/  ← baseten.rs, spawn
├── crates/buzz-agent/               ← MCP hooks, ACP
├── crates/buzz-workflow/            ← YAML triggers
└── docs/MCP_DRIVEN_HOOKS.md

upstream (reference only)
├── 06-pipelines/                    ← 010 spec, Grok fleet, agent-brain
├── cloud-agent/                     ← Daytona MCP
├── baseten-chain-mcp/               ← governed chains
└── px-validate/                     ← formal MCP
```

## Verification per slice

| Slice | Command |
|-------|---------|
| P0 | `cat specs/011-buzz-durable-agent-platform/checklists/requirements.md` |
| S01–S06 | `just ci` (when code lands) |
| S03 | `cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten` | **BLOCKED local**; CI `baseten-arm64-smoke` on macos-14 |
| S04 | `bash scripts/smoke-formal-gate.sh` |
| S02,S06 | `bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-platform-loop.sh` |
| S02 | `bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh` |

## Manifest rows

| Row ID | Slice | Status |
|--------|-------|--------|
| `PRODUCT-B-buzz-durable-agent-platform` | S06 | **covered** (mock 4/4 + production relay wake) |
| `PRODUCT-B-agent-dispatch` | S01 | **covered** |
| `PRODUCT-B-daytona-do` | S02 | **covered** |
| `PRODUCT-B-baseten-think` | S03 | open (docs gate met; pending `cargo test baseten`) |
| `PRODUCT-B-formal-hooks` | S04 | **covered** |
| `PRODUCT-B-temporal-handoff` | S05 | open (docs gate met; upstream T052) |

See `ontology-flow/test-manifest.yaml`.
