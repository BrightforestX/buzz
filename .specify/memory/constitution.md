# Buzz Constitution

## Inherited: Section IX — Durable agent platform

*(From `06-pipelines/.specify/memory/constitution.md` Section IX — unchanged)*

Agent flows that spend Baseten credits, mutate repos in sandboxes, or write to Surreal MUST be Temporal-backed when `TEMPORAL_*` is configured. Baseten governed execution MUST call `validate_chain_spec` before `submit_chain_job`. Formal verification (`formal/run.sh` and/or px-validate gates) MUST pass before ontology or validated-memory writes. Grok personas MUST NOT duplicate chain HTTP owned by the agent-brain worker. Think / Do / Verify: Baseten chainlets → Daytona sandbox → formal gates (see upstream `specs/010-durable-agent-platform/`).

Buzz implements the **desktop + buzz-agent + workflow** surface of this platform. Upstream `06-pipelines` owns Grok fleet, agent-brain conductor, and ontology formal trees.

---

## Section X — Buzz durable agent platform (fork rules)

### X.I Nostr-first platform state

New durable agent platform state MUST be modeled as Nostr events (new kinds in `buzz-core/src/kind.rs`) or workflow definitions — not ad-hoc HTTP JSON APIs. Prefer `buzz-workflow` YAML triggers and relay handlers over new endpoints.

### X.II MCP lifecycle hooks

- Tools whose bare name starts with `_` are lifecycle hooks per `docs/MCP_DRIVEN_HOOKS.md`.
- Hooks MUST be filtered from the LLM tool list and rejected if the model calls them directly.
- Hooks are **off by default**. Operator MUST set `MCP_HOOK_SERVERS` (`*` or comma-separated server names) to opt in.
- Hook timeout: `BUZZ_AGENT_HOOK_TIMEOUT_MS` (default 2500). Stop budget: `BUZZ_AGENT_STOP_MAX_REJECTIONS` (default 3).
- In-process reply guard (`BUZZ_AGENT_REQUIRE_REPLY`) shares the `_Stop` budget — not an MCP hook.
- Hook implementations MUST NOT ship inside `buzz-dev-mcp` unless explicitly reviewed for advisory-only behavior.

### X.III Baseten transport authority

- Native Baseten provider env translation MUST go through `desktop/src-tauri/src/managed_agents/baseten.rs` only.
- `apply_baseten_env` / `baseten_process_env` are the sole desktop spawn path for Baseten → OpenAI-compat transport.
- Governed Baseten **chain** jobs (`validate_chain_spec`, `submit_chain_job`) MUST use upstream `baseten-chain-mcp` — never raw chain HTTP from desktop or Tauri.
- Do not duplicate `baseten.rs` resolution order in TypeScript or workflow YAML.

### X.IV Agent configuration discipline

`desktop/src/features/agents/AGENTS.md` is binding for all agent config UI and persistence:

- Harness capability facts: single source in Rust `KnownAcpRuntime` catalog.
- No hardcoded harness-ID checks in render components.
- Effort is spawn-scoped and save-gated — no live mid-conversation effort switching.
- Run-location warnings for shared access (`anyone` / `allowlist`) MUST use `agentAccessWarning.ts`.

Violations are constitution failures, not style nits.

### X.V Phase discipline and upstream sync

| Rule | Detail |
|------|--------|
| Spec hierarchy | Local `specs/011-buzz-durable-agent-platform/` integrates upstream `010`; 011 does not replace 010 |
| Phase 0 | Docs scaffold only — no production Rust/TS without checklist update |
| Slices S01–S06 | Each slice closes manifest row + gap in `.gsd/gaps/tracking.md` |
| Evidence | Record under `.gsd/evidence/` before claiming slice complete |
| Secrets | Never commit `.env` values; reference `.env.example` only |
| Quality | `just ci` before PR when code changes touch agent surfaces |

### X.VI Fail-closed verification

1. Formal hook or px-validate rejection → no validated relay write
2. Missing Baseten/Daytona/Temporal credentials → visible failure, not silent queue
3. MCP hook server missing from allowlist → hooks not invoked (not crash)
4. Upstream formal gate failure → Do stage skipped (per 010 US5)

---

## Security (Buzz-specific)

- Managed agent shared access (`anyone` / `allowlist`) MUST disclose stakes via `agentAccessWarning` copy.
- Remote agents MUST NOT imply owner filesystem access in warning text.
- Hook output is JSON-encoded and lower trust than system prompts.

## Quality Gates

- `just ci` when production code changes.
- `cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten` when touching `baseten.rs`.
- Upstream `smoke-platform-loop.sh` for cross-repo platform slices.
- Agent config changes require matching `desktop/src/features/agents/AGENTS.md` update or explicit "no rules changed" note.

## Governance

Local spec `specs/011-buzz-durable-agent-platform/spec.md` + this constitution define Buzz platform truth. Amendments logged in `.gsd/DECISIONS.md`. Upstream ontology constitution remains authoritative for ontology loop (not in Buzz fork scope).

**Version**: 1.0.0 | **Ratified**: 2026-09-08 | **Inherits**: 06-pipelines Constitution IX (v1.2.0)
