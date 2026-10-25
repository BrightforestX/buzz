import * as React from "react";

import {
  useScenarioMirofishExperimentDetail,
  useScenarioMirofishExperiments,
} from "@/features/scenarios/hooks/useScenarioData";
import { reportSummaryFromResults } from "@/features/scenarios/scenarioExperimentTypes";
import {
  runCustomerScenarioFleet,
  runScenarioMirofishExperimentFixture,
  type CustomerScenarioFleetResult,
} from "@/features/scenarios/scenarioExperimentFetch";
import { Button } from "@/shared/ui/button";

type Props = {
  selectedExperimentId: string | null;
  onSelectExperiment: (experimentId: string, graphId: string | null) => void;
};

export function ScenarioExperimentsPanel({
  selectedExperimentId,
  onSelectExperiment,
}: Props) {
  const list = useScenarioMirofishExperiments();
  const detail = useScenarioMirofishExperimentDetail(
    selectedExperimentId ?? undefined,
  );
  const [runError, setRunError] = React.useState<string | null>(null);
  const [runBusy, setRunBusy] = React.useState(false);
  const [fleetBusy, setFleetBusy] = React.useState(false);
  const [fleetReport, setFleetReport] =
    React.useState<CustomerScenarioFleetResult | null>(null);

  const reportSummary = reportSummaryFromResults(detail.data?.results);

  const runFixtureScenario = async () => {
    setRunError(null);
    setRunBusy(true);
    try {
      await runScenarioMirofishExperimentFixture();
      await list.refetch();
    } catch (error) {
      setRunError(error instanceof Error ? error.message : String(error));
    } finally {
      setRunBusy(false);
    }
  };

  const runCustomerFleet = async () => {
    setRunError(null);
    setFleetBusy(true);
    try {
      const result = await runCustomerScenarioFleet();
      setFleetReport(result);
      await list.refetch();
    } catch (error) {
      setRunError(error instanceof Error ? error.message : String(error));
    } finally {
      setFleetBusy(false);
    }
  };

  return (
    <section className="space-y-3 rounded-xl border border-border/70 bg-card/40 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-medium">MiroFish experiments (Surreal)</h2>
        <div className="flex flex-wrap gap-2">
          <Button
            disabled={fleetBusy || runBusy}
            onClick={() => void runCustomerFleet()}
            size="sm"
            type="button"
            variant="secondary"
          >
            {fleetBusy ? "Running fleet…" : "Run customer scenario fleet"}
          </Button>
          <Button
            disabled={runBusy || fleetBusy}
            onClick={() => void runFixtureScenario()}
            size="sm"
            type="button"
          >
            {runBusy ? "Running…" : "Run fixture scenario"}
          </Button>
          <Button
            disabled={list.isFetching}
            onClick={() => void list.refetch()}
            size="sm"
            type="button"
            variant="outline"
          >
            Refresh list
          </Button>
        </div>
      </div>

      {runError ? <p className="text-xs text-destructive">{runError}</p> : null}

      {fleetReport ? (
        <p
          className="text-xs text-muted-foreground"
          data-testid="scenario-fleet-report"
        >
          Fleet: {fleetReport.passed ?? 0}/{fleetReport.catalog_size ?? "?"}{" "}
          passed
          {fleetReport.report_path ? ` · ${fleetReport.report_path}` : ""}
        </p>
      ) : null}

      {list.isLoading ? (
        <p className="text-xs text-muted-foreground">Loading experiments…</p>
      ) : null}

      {list.isError ? (
        <p className="text-xs text-destructive">
          {list.error instanceof Error
            ? list.error.message
            : "Failed to load experiments"}
        </p>
      ) : null}

      {!list.isLoading && !list.isError && (list.data?.length ?? 0) === 0 ? (
        <p className="text-xs text-muted-foreground">
          No experiments in{" "}
          <code className="rounded bg-muted px-1">mirofish_experiments_v2</code>
          . Run{" "}
          <code className="rounded bg-muted px-1">
            baseten-chain-mcp/scripts/buzz-mirofish-experiment-flow.py
          </code>
          .
        </p>
      ) : null}

      <ul
        className="max-h-40 space-y-1 overflow-y-auto text-xs"
        data-testid="scenario-experiments-list"
      >
        {(list.data ?? []).map((row) => {
          const active = row.experimentId === selectedExperimentId;
          return (
            <li key={row.experimentId}>
              <button
                className={`w-full rounded-lg border px-2 py-1.5 text-left transition-colors ${
                  active
                    ? "border-primary/50 bg-primary/10"
                    : "border-border/60 hover:bg-muted/40"
                }`}
                onClick={() =>
                  onSelectExperiment(row.experimentId, row.graphId ?? null)
                }
                type="button"
              >
                <div className="font-medium">
                  {row.title ?? row.experimentId}
                </div>
                <div className="text-muted-foreground">
                  {row.status ?? "unknown"}
                  {row.reportId ? ` · report ${row.reportId}` : ""}
                  {row.graphId ? ` · graph ${row.graphId}` : ""}
                </div>
              </button>
            </li>
          );
        })}
      </ul>

      {selectedExperimentId ? (
        <div
          className="space-y-1 border-t border-border/60 pt-2 text-xs"
          data-testid="scenario-experiment-report"
        >
          <div className="font-medium">Report preview</div>
          {detail.isLoading ? (
            <p className="text-muted-foreground">Loading synced results…</p>
          ) : null}
          {detail.isError ? (
            <p className="text-destructive">
              {detail.error instanceof Error
                ? detail.error.message
                : "Failed to load report"}
            </p>
          ) : null}
          {reportSummary ? (
            <p className="leading-relaxed text-foreground">{reportSummary}</p>
          ) : null}
          {!detail.isLoading && !reportSummary && detail.data ? (
            <p className="text-muted-foreground">
              Synced keys:{" "}
              {detail.data.results && typeof detail.data.results === "object"
                ? Object.keys(
                    detail.data.results as Record<string, unknown>,
                  ).join(", ")
                : "none — run sync on experiment"}
            </p>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
