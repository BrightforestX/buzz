import assert from "node:assert/strict";
import test from "node:test";

import { reportSummaryFromResults } from "./scenarioExperimentTypes.ts";

test("reportSummaryFromResults reads report.summary", () => {
  const summary = reportSummaryFromResults({
    report: { summary: "Stakeholders aligned on rollout." },
  });
  assert.equal(summary, "Stakeholders aligned on rollout.");
});

test("reportSummaryFromResults returns null when report missing", () => {
  assert.equal(reportSummaryFromResults({ simulation: {} }), null);
});
