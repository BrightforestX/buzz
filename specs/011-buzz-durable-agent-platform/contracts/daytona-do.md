# Contract: Daytona Do (Buzz remote execution)

**Spec**: [011-buzz-durable-agent-platform](../spec.md)

**Status**: S02 complete — Buzz remote backend mapping + cloud-agent MCP handoff documented.

**Upstream reference**: [010 daytona-sandbox.md](../../../06-pipelines/specs/010-durable-agent-platform/contracts/daytona-sandbox.md)

**Related**: [mcp-registry.md](./mcp-registry.md) § `buzz-backend-*` → cloud-agent MCP handoff

---

## Purpose

Define how Buzz **Do** (tool execution / host mutation) stays isolated from the operator desktop when platform jobs run remotely. Buzz never embeds the Daytona SDK in Tauri; platform Do flows through **cloud-agent Mastra MCP** or provider-hosted execution on `buzz-backend-*`.

## Platform phase placement

| Phase | Upstream persona | Buzz Do surface |
|-------|------------------|-----------------|
| **Do** | `daytona-sandbox-operator` | cloud-agent `daytona-*` MCP tools **or** remote agent on `buzz-backend-*` |
| Dispatch | (S01) workflow mention | Wakes agent; Do still runs in agent session |
| Think | Baseten / inline LLM | Not Do — no host writes |
| Verify | formal-gate MCP hooks | Read-only gate before stop |
| Durability | Temporal + workflow run | Sandbox id in state file; destroy on completion |

---

## Buzz run-location model

Buzz distinguishes **where the agent process runs** from **where Do tools execute**.

| Backend | `ManagedAgentBackend.type` | Agent process | Do default | Access warning |
|---------|---------------------------|---------------|------------|----------------|
| Local | `local` | Operator machine | `buzz-dev-mcp` on same host | "your computer…" |
| Remote provider | `provider` | `buzz-backend-*` host (K8s, workstation, etc.) | Provider env + attached MCP | "the server it runs on…" |
| Platform batch (operator) | N/A (not desktop UI) | cloud-agent MCP caller | Daytona sandbox | N/A |

### Code anchors (desktop)

| Concern | File |
|---------|------|
| Run location copy | `desktop/src/features/agents/lib/agentAccessWarning.ts` |
| Provider discovery | `desktop/src-tauri/src/managed_agents/backend.rs` (`discover_provider_candidates`, `resolve_provider_binary`) |
| Where-to-run UI | `desktop/src/features/agents/ui/whereToRunIntent.ts`, `AgentRunLocationContext.tsx` |
| relay-mesh (shared compute) | Provider id `relay-mesh` → forces `buzz-agent` runtime; still **local** spawn unless `runOn` is a backend |

### Provider binary convention

- Executables on PATH: `buzz-backend-{id}` (e.g. `buzz-backend-kubernetes`)
- Id extracted from filename prefix; validated `[a-z0-9][a-z0-9_-]*`
- Desktop **never** executes arbitrary paths — only PATH-discovered binaries via `resolve_provider_binary`

### Known providers (Buzz repo)

| Provider id | Crate / path | Host type | Daytona? |
|-------------|--------------|-----------|----------|
| `kubernetes` | `crates/buzz-backend-kubernetes/` | K8s pod | No — cluster isolation |
| *(operator)* | `buzz-backend-{custom}` on PATH | VM / bare metal | Operator-defined |

**Rule**: `buzz-backend-*` provides **agent hosting**, not automatic Daytona. Platform **isolated Do** for ontology jobs uses cloud-agent MCP directly (operator or upstream Grok fleet), not the K8s backend crate.

---

## Primary path: cloud-agent Mastra MCP

**Package**: `../cloud-agent/src/mastra/tools/daytona-tools.ts`  
**Launcher**: `../cloud-agent/scripts/run-mastra-mcp.sh`

```bash
cd ../cloud-agent
SANDBOX_PROVIDER=daytona bash scripts/run-mastra-mcp.sh
```

MCP server loads env via `dotenv` in `mcp-server.ts` — do not `source .env` in shell (unquoted values break parsing).

### Tool sequence (mandatory order)

```
daytona-create
  → daytona-bootstrap    # git clone, deps (GIT_REPO_URL)
  → daytona-exec         # Do commands (npm test, scripts, etc.)
  → daytona-destroy      # ALWAYS — success or failure
```

Optional diagnostics (not in minimal loop): `daytona-connectivity`, `daytona-shell`.

Formal / SHACL microservices may use packed tools: `px_sandbox_create`, `px_sandbox_destroy` (same fail-closed destroy rule).

### Required environment

| Variable | Purpose |
|----------|---------|
| `DAYTONA_API_KEY` | API authentication |
| `DAYTONA_ORGANIZATION_ID` | Org scope |
| `SANDBOX_PROVIDER` | Must be `daytona` |
| `GIT_REPO_URL` | Clone target in sandbox |
| `GIT_TOKEN` or `GITHUB_TOKEN` | Private repo access |
| `CLOUD_AGENT_DAYTONA_STATE_FILE` | Persisted sandbox id (default `/tmp/cloud-agent-daytona-sandbox.json`) |

Optional: `DAYTONA_SNAPSHOT`, `DAYTONA_API_URL`, `DAYTONA_TARGET`, `GPU_INFERENCE_STACK_DIR`, `DAYTONA_AUTO_STOP_MINUTES` (capped at 5 min in tool).

### State file

- Written on `daytona-create`; read by bootstrap/exec/destroy
- `daytona-destroy` clears state and releases client even on partial failure
- Stale sandbox: operator runs `daytona-destroy` or pybatch `reap_daytona.py` (batch fleet only)

---

## Buzz desktop responsibilities

1. **Surface run location** in create/edit/profile (`RespondToField` + `agentAccessWarningText`)
2. **Discover** `buzz-backend-*` on PATH; show "Run on" only when providers exist
3. **Deploy remote agents** via validated provider binary — agent harness + MCP config on provider host
4. **Pass `policy_env`** for remote effort at deploy time (effort picker local-only per AGENTS.md rule 14)
5. **Never** embed Daytona SDK in Tauri or call Daytona HTTP from desktop Rust

### Remote agent Do path (production)

When agent `backend.type === "provider"`:

```
Desktop deploy → buzz-backend-{id} launches agent pod/VM
  → buzz-agent subprocess on provider host
  → MCP tools configured on agent (operator responsibility)
  → Do executes on provider host filesystem/APIs
```

Platform **Daytona-isolated** Do is **not** automatic for remote agents. Operator must either:

- Attach **cloud-agent-mastra** MCP to the agent's MCP server list (stdio/SSE from provider), or
- Run Do via upstream 06-pipelines batch (Grok `daytona-sandbox-operator`) outside desktop UI

### Local agent Do path (dev)

```
Desktop local spawn → buzz-agent on operator machine
  → buzz-dev-mcp (shell/file edit) on same host
  → NOT platform Do — dev only; access warning applies
```

---

## Workflow → remote Do (cross-slice)

Combines [S01 dispatch](./mcp-registry.md) with Do:

1. Workflow `send_message` @mention wakes deployed **remote** agent
2. Agent session on `buzz-backend-*` runs Think + Do via configured MCP
3. For **platform** jobs requiring Daytona isolation, upstream operator invokes cloud-agent MCP **in parallel** or via agent MCP config — not via workflow action (no `invoke_daytona` step in `buzz-workflow` schema v1)

---

## Fail-closed rules

| Rule | Rationale |
|------|-----------|
| **Always `daytona-destroy`** after create, even on exec failure | Cost + data isolation |
| **No silent host writes** when MCP unreachable | Log `DAYTONA_FALLBACK=shell` before any shell script path |
| **No Daytona SDK in desktop** | Constitution X — delegate to cloud-agent or provider |
| **Invalid provider id rejected** | `resolve_provider_binary` blocks path traversal |
| **Destroy with empty sandbox id fails loudly** | Prevents false "cleaned up" signal |
| **auto_stop ≤ 5 minutes** | cloud-agent default cap on sandbox billing |
| **Remote access warning names server scope** | Not owner's local files — `agentAccessWarning.ts` |
| **Do not run platform Do on operator laptop** without explicit operator consent | Local = dev path only in stack precedence |

---

## Fallback path (I&T only)

When Mastra MCP is unreachable:

```bash
# From 06-pipelines (operator machine)
bash scripts/daytona_ontology.sh
bash scripts/daytona-compose.sh
```

Must log: `DAYTONA_FALLBACK=shell` — never silent host mutation.

Buzz desktop UI **does not** trigger fallback scripts in v1.

---

## Stack precedence

| Priority | Stack | When |
|----------|-------|------|
| 1 | cloud-agent Mastra MCP (`daytona-*`) | Platform Do jobs, formal batch |
| 2 | `buzz-backend-*` provider + agent MCP on host | Production remote agents |
| 3 | Local managed agent + `buzz-dev-mcp` | Dev only — not platform Do |
| 4 | 06-pipelines shell scripts | MCP down, ontology I&T |
| 5 | Cursor `user-daytona-mcp` | Human operator / assistant-ui fleet |

---

## Verification

### Upstream smoke (S02 gate)

```bash
bash ../../06-pipelines/specs/010-durable-agent-platform/scripts/smoke-daytona-operator.sh
```

- **Without** `DAYTONA_API_KEY`: dry-run PASS (launcher + contract check)
- **With** keys: PASS after env OK; live sandbox create **not** run in smoke script (manual MCP)

### Desktop unit tests (hermetic)

```bash
cd desktop
node --import ./test-loader.mjs --experimental-strip-types --test \
  src/features/agents/lib/agentAccessWarning.test.mjs
```

### Playwright (reference — not required for S02 docs gate)

| Spec | Covers |
|------|--------|
| `tests/e2e/agent-access-warning.spec.ts` | Local vs remote warning copy |
| `tests/e2e/edit-agent-run-on.spec.ts` | Run-on field for provider backends |
| `tests/e2e/where-to-run-config.spec.ts` | `buzz-backend-kubernetes` mock |

---

## Open items (post-S02)

- [ ] Wire `buzz-backend-*` deploy to inject cloud-agent MCP endpoint env (code PR)
- [ ] CI matrix: smoke-daytona-operator in Buzz fork nightly
- [ ] Live E2E: agent on K8s backend + Daytona MCP attached (S06)
- [ ] Document px_sandbox_* vs daytona-* tool choice for formal Do
