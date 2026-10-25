#!/usr/bin/env node
/**
 * Lane B red/green self-test (runs on macOS where WebDriver probe skips).
 * Validates invoke probe script expectations without launching tauri-driver.
 */
import assert from "node:assert/strict";

const probeSource = `
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
  return { ok: true };
`;

async function runInFakeWebview(invokeImpl) {
  const window = {
    __TAURI_INTERNALS__: {
      invoke: invokeImpl,
    },
  };
  const fn = new Function(
    "window",
    `return (async () => { ${probeSource} })()`,
  );
  return fn(window);
}

// Green: happy path
await runInFakeWebview(async (cmd, args) => {
  if (cmd === "get_agent_mcp_settings") {
    return { chainMcpEnabled: true, mirofishMcpEnabled: true };
  }
  if (cmd === "set_agent_mcp_settings") {
    return {
      chainMcpEnabled: args.chainMcpEnabled,
      mirofishMcpEnabled: args.mirofishMcpEnabled,
    };
  }
  throw new Error(`unexpected ${cmd}`);
});

// Red: missing invoke
let threw = false;
try {
  await runInFakeWebview(undefined);
} catch (error) {
  threw = true;
  assert.match(String(error), /invoke is missing/);
}
assert.equal(threw, true, "expected missing invoke to throw");

// Red: unknown command
threw = false;
try {
  await runInFakeWebview(async (cmd) => {
    throw new Error(`Command ${cmd} not found`);
  });
} catch (error) {
  threw = true;
  assert.match(String(error), /not found/);
}
assert.equal(threw, true, "expected unknown command to throw");

await import("selenium-webdriver");
console.log(
  "Lane B self-test OK (invoke contract + selenium-webdriver import)",
);
