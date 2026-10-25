# Evidence — Buzz wire/integration tick 2 (2026-09-08)

**Milestone:** M-buzz-platform | **Prior:** [20260908-buzz-wire-tick1.md](./20260908-buzz-wire-tick1.md)

## Tasks executed

### 1. E2E build + Playwright

| Step | Result |
|------|--------|
| `. ./bin/activate-hermit && cd desktop && pnpm build:e2e` | **PASS** (~13s) |
| Register specs in `playwright.config.ts` smoke `testMatch` | **done** |
| Fix `ontology-preflight.spec.ts` ESM paths (`import.meta.url`) | **done** |
| `pnpm exec playwright test ontology-preflight platform-closed-loop --project=smoke` | **PASS** — 3 tests |

**Playwright breakdown**

| Spec | Tests | Result |
|------|-------|--------|
| `ontology-preflight.spec.ts` | 2 (YAML + config contract) | PASS |
| `platform-closed-loop.spec.ts` | 1 (webhook workflow on #agents) | PASS |

**Note:** Passing explicit file paths with `--project=integration` fails (specs not in integration `testMatch`). Use `--project=smoke` or name pattern (`platform-closed-loop`).

### 2. BUZZ_PLATFORM_JOB_ID passthrough

**Deferred** — no Tauri spawn change this tick (requires wake-context plumbing from workflow webhook → agent harness).

### 3. Baseten unit tests (hermit)

```bash
cargo test --manifest-path desktop/src-tauri/Cargo.toml baseten
```

**BLOCKED** — same arm64 linker error: undefined `opus_*` symbols (`libopus` not linked). Hermit does not resolve; needs CI arm64 runner with libopus or local `brew install opus` + link flags.

## Files changed (tick 2)

| File | Change |
|------|--------|
| `desktop/playwright.config.ts` | Added `platform-closed-loop`, `ontology-preflight` to smoke project |
| `desktop/tests/e2e/ontology-preflight.spec.ts` | ESM-safe paths via `import.meta.url` |

## Manifest status

| Row | Status | Notes |
|-----|--------|-------|
| `PRODUCT-B-agent-dispatch` | covered | unchanged |
| `PRODUCT-B-buzz-durable-agent-platform` | **open** | mock workflow stub green; full dispatch→agent wake not wired |
| `PRODUCT-B-baseten-think` | **open** | opus linker |
| `PRODUCT-B-temporal-handoff` | **open** | upstream 010 T052 |

No manifest rows closed this tick (PRODUCT row requires full closed loop).

## Tick 3 priority

1. **S05 wire:** `BUZZ_PLATFORM_JOB_ID` / `BUZZ_PLATFORM_TENANT` in Tauri managed-agent spawn when workflow webhook context is available.
2. **S06 extend:** `platform-closed-loop.spec.ts` — deploy managed agent + mock webhook POST → assert dispatch ack.
3. **S03 test gate:** arm64 CI `cargo test baseten` or document libopus install for local dev.
4. **Upstream:** 010 T052 `platformConductorWorkflow.ts` for temporal manifest.
