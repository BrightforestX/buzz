# M-buzz-platform CONTEXT — Buzz Durable Agent Platform

**Updated:** 2026-09-08

## Cross-repo refs

| Ref | Path from buzz root |
|-----|---------------------|
| Local spec 011 | `specs/011-buzz-durable-agent-platform/spec.md` |
| Upstream spec 010 | `../../06-pipelines/specs/010-durable-agent-platform/spec.md` |
| Cross-repo map | `../../06-pipelines/specs/010-durable-agent-platform/docs/cross-repo-map.md` |
| 06-pipelines GSD | `../../06-pipelines/.gsd/STATE.md` |
| cloud-agent GSD | `../cloud-agent/.gsd/STATE.md` |
| baseten-chain-mcp GSD | `../../baseten-chain-mcp/.gsd/STATE.md` |
| Chain IDs | `../gpu-inference-stack/config/baseten-chain-ids.json` |
| px-validate formal | `../../../../Brightforest/projects/tools/px-validate/formal/` |
| MCP hooks | `docs/MCP_DRIVEN_HOOKS.md` |
| Agents rules | `desktop/src/features/agents/AGENTS.md` |
| baseten.rs | `desktop/src-tauri/src/managed_agents/baseten.rs` |

## Environment keys (no values in git)

| Key | Buzz surface | Pillar |
|-----|--------------|--------|
| `MCP_HOOK_SERVERS`, `BUZZ_AGENT_HOOK_TIMEOUT_MS`, `BUZZ_AGENT_STOP_MAX_REJECTIONS` | buzz-agent | Verify |
| `BASETEN_API_KEY`, `BASETEN_MODEL_ID`, `BASETEN_MODEL_APIS_BASE` | baseten.rs | Think |
| `BUZZ_AGENT_PROVIDER`, `OPENAI_COMPAT_*` | buzz-agent (derived) | Think |
| `DAYTONA_*`, `SANDBOX_PROVIDER` | upstream MCP / remote backend | Do |
| `TEMPORAL_*` | upstream agent-brain | Durability |

## Buzz-specific decisions

- 011 is local fork spec — upstream 010 remains source of truth for Grok/Temporal/conductor
- `baseten.rs` is sole Baseten transport authority for desktop spawn
- MCP hooks off by default; constitution Section X.II
- Phase 0 complete — no production code changes

See `.gsd/DECISIONS.md`.

## Open code tasks (S01+)

| Slice | Primary files |
|-------|---------------|
| S01 | `crates/buzz-workflow/`, `desktop/src/features/agents/` |
| S02 | remote backend providers, `contracts/daytona-do.md` |
| S03 | `baseten.rs`, `.env.example` comments |
| S04 | `crates/buzz-agent/`, hook tests |
| S05 | `crates/buzz-workflow/`, upstream `platformConductorWorkflow.ts` |
| S06 | E2E specs, evidence file |

## Gaps

Canonical open items: `.gsd/gaps/tracking.md`
