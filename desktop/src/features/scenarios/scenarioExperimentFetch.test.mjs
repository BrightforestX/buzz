import assert from "node:assert/strict";
import test from "node:test";

import { isUnknownTauriCommandError } from "./scenarioExperimentFetch.ts";

test("isUnknownTauriCommandError detects missing Tauri command", () => {
  assert.equal(
    isUnknownTauriCommandError(
      new Error("Command run_scenario_mirofish_experiment_fixture not found"),
    ),
    true,
  );
  assert.equal(
    isUnknownTauriCommandError(new Error("SurrealDB HTTP 400")),
    false,
  );
});
