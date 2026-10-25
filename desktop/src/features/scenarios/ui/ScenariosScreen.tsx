import * as React from "react";
import { getRouteApi } from "@tanstack/react-router";

import {
  queryScenarioSurreal,
  useMirofishGraph,
  useScenarioStackStatus,
} from "@/features/scenarios/hooks/useScenarioData";
import { scenarioGraphErrorMessage } from "@/features/scenarios/scenarioGraphFetch";
import { ScenarioExperimentsPanel } from "@/features/scenarios/ui/ScenarioExperimentsPanel";
import { ScenarioGraphCanvas } from "@/features/scenarios/ui/ScenarioGraphCanvas";
import { Button } from "@/shared/ui/button";
import { Input } from "@/shared/ui/input";
import { TopChromeInsetHeader } from "@/shared/layout/TopChromeInsetHeader";

const DEFAULT_GRAPH = "graph_mcp_eval_fixture";
const DEFAULT_SURREAL_QUERY =
  "SELECT issue_id, summary, status, priority FROM pm_issue LIMIT 8;";

const scenariosRouteApi = getRouteApi("/scenarios");

export function ScenariosScreen() {
  const navigate = scenariosRouteApi.useNavigate();
  const { graphId: searchGraphId } = scenariosRouteApi.useSearch();
  const graphId = searchGraphId ?? DEFAULT_GRAPH;
  const [graphInput, setGraphInput] = React.useState(graphId);
  const [sql, setSql] = React.useState(DEFAULT_SURREAL_QUERY);
  const [sqlResult, setSqlResult] = React.useState<string>("");
  const [sqlError, setSqlError] = React.useState<string | null>(null);
  const [selectedExperimentId, setSelectedExperimentId] = React.useState<
    string | null
  >(null);

  const stack = useScenarioStackStatus();
  const graph = useMirofishGraph(graphId);

  React.useEffect(() => {
    setGraphInput(graphId);
  }, [graphId]);

  const applyGraphId = () => {
    void navigate({
      search: { graphId: graphInput.trim() || DEFAULT_GRAPH },
    });
  };

  const runSurrealQuery = async () => {
    setSqlError(null);
    try {
      const result = await queryScenarioSurreal(sql);
      setSqlResult(JSON.stringify(result, null, 2));
    } catch (error) {
      setSqlError(error instanceof Error ? error.message : String(error));
    }
  };

  const status = stack.data;

  return (
    <div
      className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden"
      data-testid="scenarios-view"
    >
      <TopChromeInsetHeader data-tauri-drag-region flush>
        <header className="flex min-w-0 items-center gap-3 px-5 py-3">
          <div className="min-w-0 flex-1">
            <h1 className="text-base font-semibold">Scenarios</h1>
            <p className="text-xs text-muted-foreground">
              MiroFish graph, experiment reports (Surreal), and PM context
            </p>
          </div>
        </header>
      </TopChromeInsetHeader>

      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4 pb-6 pt-4 sm:px-6">
        <section className="grid gap-2 rounded-xl border border-border/70 bg-card/40 p-3 text-xs sm:grid-cols-3">
          <div>
            Trino{" "}
            <span
              className={
                status?.trinoReady ? "text-green-600" : "text-amber-600"
              }
            >
              {status?.trinoReady ? "ready" : "down"}
            </span>
            <div className="truncate text-muted-foreground">
              {status?.trinoUrl}
            </div>
          </div>
          <div>
            Surreal{" "}
            <span
              className={
                status?.surrealReady ? "text-green-600" : "text-amber-600"
              }
            >
              {status?.surrealReady ? "ready" : "down"}
            </span>
            <div className="truncate text-muted-foreground">
              {status?.surrealUrl}
            </div>
          </div>
          <div>
            MiroFish{" "}
            <span
              className={
                status?.mirofishReady ? "text-green-600" : "text-amber-600"
              }
            >
              {status?.mirofishReady ? "ready" : "down"}
            </span>
            <div className="truncate text-muted-foreground">
              {status?.mirofishBaseUrl}
            </div>
          </div>
        </section>

        <ScenarioExperimentsPanel
          onSelectExperiment={(experimentId, graphIdFromRow) => {
            setSelectedExperimentId(experimentId);
            if (graphIdFromRow?.trim()) {
              void navigate({
                search: { graphId: graphIdFromRow.trim() },
              });
            }
          }}
          selectedExperimentId={selectedExperimentId}
        />

        <div className="flex flex-wrap items-end gap-2">
          <div className="min-w-[240px] flex-1">
            <label className="text-xs font-medium" htmlFor="graph-id">
              Graph id
            </label>
            <Input
              id="graph-id"
              onChange={(event) => setGraphInput(event.target.value)}
              value={graphInput}
            />
          </div>
          <Button onClick={applyGraphId} type="button" variant="secondary">
            Load graph
          </Button>
          <Button
            onClick={() => void graph.refetch()}
            type="button"
            variant="outline"
            disabled={graph.isFetching}
          >
            Refresh
          </Button>
        </div>

        {graph.isLoading ? (
          <p className="text-sm text-muted-foreground">Loading graph…</p>
        ) : null}

        {graph.isError ? (
          <p className="text-sm text-destructive">
            {scenarioGraphErrorMessage(graph.error)}
          </p>
        ) : null}

        <ScenarioGraphCanvas
          edges={graph.data?.edges ?? []}
          nodes={graph.data?.nodes ?? []}
        />

        <section className="space-y-2">
          <h2 className="text-sm font-medium">
            Surreal context (agent discussions)
          </h2>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-border bg-background px-3 py-2 font-mono text-xs"
            onChange={(event) => setSql(event.target.value)}
            value={sql}
          />
          <Button
            onClick={() => void runSurrealQuery()}
            type="button"
            size="sm"
          >
            Run query
          </Button>
          {sqlError ? (
            <p className="text-sm text-destructive">{sqlError}</p>
          ) : null}
          {sqlResult ? (
            <pre className="max-h-48 overflow-auto rounded-lg border border-border/70 bg-muted/30 p-3 text-xs">
              {sqlResult}
            </pre>
          ) : null}
        </section>

        <p className="text-xs text-muted-foreground">
          Stack:{" "}
          <code className="rounded bg-muted px-1">
            ./scripts/buzz-stack-up.sh
          </code>{" "}
          (Trino, Surreal, zep-shim, MiroFish). Graph fixture:{" "}
          <code className="rounded bg-muted px-1">
            python3 scripts/seed-mirofish-graph-fixture.py
          </code>{" "}
          (needs Ollama). Open{" "}
          <code className="rounded bg-muted px-1">
            #/scenarios?graphId=graph_mcp_eval_fixture
          </code>
          .
        </p>
      </div>
    </div>
  );
}
