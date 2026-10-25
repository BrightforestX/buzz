#!/usr/bin/env node
/**
 * Lane B: real Tauri webview + Rust invoke via tauri-driver (Linux/Windows).
 * See desktop/TESTING.md.
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const desktopRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const defaultBinary = path.join(
  desktopRoot,
  "src-tauri",
  "target",
  "debug",
  process.platform === "win32" ? "buzz-desktop.exe" : "buzz-desktop",
);

function log(msg) {
  process.stderr.write(`${msg}\n`);
}

function resolveDriverBin() {
  const configured = process.env.TAURI_DRIVER_BIN;
  if (configured) return configured;
  const home = os.homedir();
  return path.join(
    home,
    ".cargo",
    "bin",
    process.platform === "win32" ? "tauri-driver.exe" : "tauri-driver",
  );
}

function ensureDebugBinary() {
  const application =
    process.env.BUZZ_TAURI_APP_BINARY?.trim() || defaultBinary;
  if (process.env.BUZZ_SKIP_TAURI_BUILD === "1") {
    if (!fs.existsSync(application)) {
      throw new Error(
        `BUZZ_SKIP_TAURI_BUILD=1 but binary missing: ${application}`,
      );
    }
    return application;
  }

  log("Building frontend (vite production bundle for debug app)…");
  const vite = spawnSync("pnpm", ["exec", "vite", "build"], {
    cwd: desktopRoot,
    stdio: "inherit",
    shell: true,
  });
  if (vite.status !== 0) {
    throw new Error("vite build failed");
  }

  log("Building debug Tauri binary (no bundle)…");
  const tauri = spawnSync(
    process.execPath,
    [
      path.join(desktopRoot, "scripts", "tauri-command.mjs"),
      "build",
      "--debug",
      "--no-bundle",
    ],
    { cwd: desktopRoot, stdio: "inherit" },
  );
  if (tauri.status !== 0) {
    throw new Error("tauri build --debug --no-bundle failed");
  }

  if (!fs.existsSync(application)) {
    throw new Error(
      `Expected debug binary at ${application} after build; set BUZZ_TAURI_APP_BINARY`,
    );
  }
  return application;
}

async function runProbe(application) {
  const driverBin = resolveDriverBin();
  if (!fs.existsSync(driverBin)) {
    throw new Error(
      `tauri-driver not found at ${driverBin}. Run: cargo install tauri-driver --locked`,
    );
  }

  const { Builder, Capabilities } = await import("selenium-webdriver");

  let tauriDriver;
  let driver;
  let exit = false;

  const close = async () => {
    exit = true;
    try {
      await driver?.quit();
    } catch {
      /* ignore */
    }
    tauriDriver?.kill();
  };

  process.on("SIGINT", () => {
    void close().finally(() => process.exit(130));
  });

  tauriDriver = spawn(driverBin, [], {
    stdio: [null, "inherit", "inherit"],
  });
  tauriDriver.on("error", (error) => {
    log(`tauri-driver error: ${error}`);
    process.exit(1);
  });
  tauriDriver.on("exit", (code) => {
    if (!exit && code !== 0) {
      log(`tauri-driver exited with code ${code}`);
      process.exit(1);
    }
  });

  await new Promise((r) => setTimeout(r, 1500));

  const capabilities = new Capabilities();
  capabilities.set("tauri:options", { application });
  capabilities.setBrowserName("wry");

  driver = await new Builder()
    .withCapabilities(capabilities)
    .usingServer("http://127.0.0.1:4444/")
    .build();

  const probe = `
    const invoke = window.__TAURI_INTERNALS__?.invoke;
    if (typeof invoke !== "function") {
      throw new Error("window.__TAURI_INTERNALS__.invoke is missing");
    }
    const get = await invoke("get_agent_mcp_settings", {});
    if (typeof get?.chainMcpEnabled !== "boolean") {
      throw new Error("get_agent_mcp_settings returned unexpected shape");
    }
    const set = await invoke("set_agent_mcp_settings", {
      chainMcpEnabled: get.chainMcpEnabled,
      mirofishMcpEnabled: false,
      mirofishBaseUrl: null,
    });
    if (set.mirofishMcpEnabled !== false) {
      throw new Error("set_agent_mcp_settings did not persist mirofishMcpEnabled=false");
    }
    await invoke("set_agent_mcp_settings", {
      chainMcpEnabled: get.chainMcpEnabled,
      mirofishMcpEnabled: true,
      mirofishBaseUrl: null,
    });
    return { ok: true, get, set };
  `;

  const result = await driver.executeScript(probe);
  log(`WebDriver invoke probe OK: ${JSON.stringify(result)}`);
  await close();
}

async function main() {
  if (process.platform === "darwin") {
    log(
      "Skipping WebDriver invoke probe on macOS (tauri-driver WebDriver is Linux/Windows only).",
    );
    log(
      "Use Lane A (Playwright mock) + manual pnpm tauri dev, or run this on Linux CI.",
    );
    process.exit(0);
  }

  const application = ensureDebugBinary();
  log(`Using application binary: ${application}`);
  await runProbe(application);
}

main().catch((error) => {
  log(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
