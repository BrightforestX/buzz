# Buzz desktop testing

Buzz desktop uses **three automation lanes**. Pick the lane that matches what you need to prove.

| Lane | Fidelity | Speed | What it proves |
|------|----------|-------|----------------|
| **A — Mock Playwright** | UI only; IPC mocked | Fast (CI default) | React flows, invoke *payloads* logged in `__BUZZ_E2E_COMMAND_LOG__` |
| **B — Tauri WebDriver** | Real webview + **real Rust invoke** | Slow; Linux/Windows | Commands such as `get_agent_mcp_settings` against a debug binary |
| **C — Rust / scripts** | Native logic, no UI | Medium | Spawn env, MCP wiring, agent crates |

Electron-style “launch the app and attach CDP to one Chromium” is **not** the default here: Tauri uses a **system webview** and **Rust IPC**. Lane B is the closest equivalent (via [tauri-driver](https://tauri.app/develop/tests/webdriver/)).

---

## Lane A — Mock Playwright (default)

Build the e2e frontend and serve `dist/`; `e2eBridge.ts` replaces `__TAURI_INTERNALS__.invoke`.

```bash
cd 01-platform/buzz/desktop
pnpm exec vite build --mode e2e
pnpm exec playwright test --project=smoke          # subset
pnpm exec playwright test agent-mcp-settings --project=smoke
```

Orchestrated check (MCP settings example):

```bash
./scripts/verify-agent-mcp-settings.sh
```

Helpers: `tests/helpers/bridge.ts`, `tests/e2e/helpers/tauriInvoke.ts`.

**Limitation:** A stale or missing mock handler shows up as UI errors; a **real** desktop build is required to prove Rust commands exist (Lane B or manual `pnpm tauri dev`).

---

## Lane B — Tauri WebDriver (real IPC)

Requires:

- `cargo install tauri-driver --locked`
- **Linux:** `webkit2gtk-driver`, `xvfb-run` for headless CI
- **Windows:** Edge WebDriver (see Tauri WebDriver CI docs)
- **macOS:** not supported by upstream WebDriver stack; use Lane A + manual `pnpm tauri dev`, or Lane C

Build a debug app (once per Rust/frontend change):

```bash
pnpm exec vite build
node ./scripts/tauri-command.mjs build --debug --no-bundle
```

Run the invoke probe (starts `tauri-driver`, launches the binary, calls `get_agent_mcp_settings` / `set_agent_mcp_settings` inside the webview):

```bash
export BUZZ_TAURI_APP_BINARY="$PWD/src-tauri/target/debug/buzz-desktop"   # optional override
./scripts/tauri-webdriver-invoke-probe.mjs
```

Or run all lanes (A + B self-test + C; WebDriver IPC on Linux/Windows):

```bash
./scripts/run-desktop-test-lanes.sh
```

Environment:

| Variable | Purpose |
|----------|---------|
| `BUZZ_TAURI_APP_BINARY` | Path to debug executable (default: `src-tauri/target/debug/buzz-desktop`) |
| `BUZZ_SKIP_TAURI_BUILD=1` | Skip `tauri build --debug --no-bundle` |
| `BUZZ_DESKTOP_WEBDRIVER=1` | Enable Lane B in `run-desktop-test-lanes.sh` |
| `TAURI_DRIVER_BIN` | Path to `tauri-driver` (default: `~/.cargo/bin/tauri-driver`) |

---

## Lane C — Rust and agent smoke

```bash
cargo check --manifest-path src-tauri/Cargo.toml
# Unit tests in managed_agents/mcp_settings (may require full native link deps)
cargo test --manifest-path src-tauri/Cargo.toml mcp_settings:: --lib
```

Agent/MCP stack (repo root scripts):

```bash
./scripts/buzz-mirofish-live-simulation.sh
```

---

## Manual real desktop (no automation)

After Rust changes, restart the desktop shell so invoke handlers reload:

```bash
pnpm tauri dev
```

On **Apple Silicon**, if linking fails with undefined `opus_*` and Homebrew’s `libopus` is **x86_64** only, rebuild with bundled Opus:

```bash
cd src-tauri && OPUS_NO_PKG=1 cargo build -p buzz-desktop
```

If **8080** is taken (e.g. Docker Trino), start the relay with `BUZZ_HEALTH_PORT=8081` and keep `RELAY_URL=ws://localhost:3000`. Confirm the relay owns `:3000` (`curl -s http://127.0.0.1:3000/health` → `ok`), not another dev server.

Open **Settings → Agents → Agent MCP servers**. If you see “Command … not found”, the running binary predates the command — rebuild/restart.

**CDP:** In dev, use the platform web inspector on the Tauri webview (not the same as attaching Playwright to Electron). External CDP to WKWebView on macOS is limited; prefer Lane B on Linux/Windows CI or Lane A for UI regression volume.

---

## Adding tests for a new `#[tauri::command]`

1. Register in `src-tauri/src/lib.rs` `generate_handler!` (prefer `commands/` module).
2. Add a **Lane A** handler in `src/testing/e2eBridge.ts` and a Playwright spec.
3. Add **Lane B** assertions in `scripts/tauri-webdriver-invoke-probe.mjs` when the command must be proven in-process.
4. Add **Lane C** Rust unit tests for pure logic (env application, persistence).
