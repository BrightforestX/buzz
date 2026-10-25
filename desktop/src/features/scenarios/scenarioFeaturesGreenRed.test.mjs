import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const here = dirname(fileURLToPath(import.meta.url));
const desktopRoot = join(here, "../../..");

function read(rel) {
  return readFileSync(join(desktopRoot, rel), "utf8");
}

test("GREEN: Scenarios experiments panel exposes list and report test ids", () => {
  const src = read("src/features/scenarios/ui/ScenarioExperimentsPanel.tsx");
  assert.match(src, /data-testid="scenario-experiments-list"/);
  assert.match(src, /data-testid="scenario-experiment-report"/);
  assert.match(src, /runScenarioMirofishExperimentFixture/);
});

test("GREEN: useScenarioData wires experiment fetch layer", () => {
  const src = read("src/features/scenarios/hooks/useScenarioData.ts");
  assert.match(src, /fetchScenarioMirofishExperiments/);
  assert.match(src, /fetchScenarioMirofishExperimentDetail/);
});

test("RED: mirofish_scenario loopback guard and Surreal parsing (Rust source)", () => {
  const src = read("src-tauri/src/commands/mirofish_scenario.rs");
  assert.match(src, /fn loopback_http_only/);
  assert.match(src, /experimentId contains invalid characters/);
  assert.match(src, /fn parse_surreal_sql_rows/);
  assert.match(src, /fetch_graph_from_surreal_snapshot/);
});

test("GREEN: run_scenario host runner script exists", () => {
  const src = read("../scripts/buzz-scenario-run-host.sh");
  assert.match(src, /buzz-scenario-orchestrated-run\.py/);
});

test("RED: scenarioGraphFetch default zep base is loopback", () => {
  const src = read("src/features/scenarios/scenarioGraphFetch.ts");
  assert.match(src, /127\.0\.0\.1:8100/);
  assert.doesNotMatch(src, /example\.com/);
});
