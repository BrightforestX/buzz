/**
 * S01 wire stub — ontology preflight is enforced in buzz-agent (ACP session/new),
 * not the desktop shell. This spec anchors the example workflow + env contract;
 * integration proof lives in `cargo test -p buzz-agent ontology_gate`.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

import { expect, test } from "@playwright/test";

const specDir = dirname(fileURLToPath(import.meta.url));
const PLATFORM_DISPATCH_YAML = resolve(
  specDir,
  "../../../specs/011-buzz-durable-agent-platform/examples/platform-dispatch.workflow.yaml",
);

test.describe("S01 ontology preflight (wire stub)", () => {
  test("platform dispatch example documents verify via validate_proposal", () => {
    const yaml = readFileSync(PLATFORM_DISPATCH_YAML, "utf8");
    expect(yaml).toContain("validate_proposal");
    expect(yaml).toContain("trigger:");
    expect(yaml).toContain("webhook");
  });

  test("ontology gate env contract is documented in agent config", () => {
    const configSource = readFileSync(
      resolve(specDir, "../../../crates/buzz-agent/src/config.rs"),
      "utf8",
    );
    expect(configSource).toContain("BUZZ_AGENT_ONTOLOGY_GATE");
    expect(configSource).toContain("BUZZ_AGENT_ONTOLOGY_PREFLIGHT_CLASS");
  });
});
