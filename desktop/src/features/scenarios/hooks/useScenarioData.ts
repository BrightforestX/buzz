import { useQuery } from "@tanstack/react-query";

import { fetchScenarioGraph } from "@/features/scenarios/scenarioGraphFetch";
import type { MirofishGraphPayload } from "@/features/scenarios/mirofishGraphTypes";
import {
  fetchScenarioMirofishExperimentDetail,
  fetchScenarioMirofishExperiments,
} from "@/features/scenarios/scenarioExperimentFetch";
import { invoke } from "@tauri-apps/api/core";

export type ScenarioDataStackStatus = {
  trinoUrl: string;
  surrealUrl: string;
  mirofishBaseUrl: string;
  trinoReady: boolean;
  surrealReady: boolean;
  mirofishReady: boolean;
};

export function useScenarioStackStatus() {
  return useQuery({
    queryKey: ["scenario-data-stack-status"],
    queryFn: () =>
      invoke<ScenarioDataStackStatus>("get_scenario_data_stack_status"),
    refetchInterval: 30_000,
  });
}

export function useMirofishGraph(graphId: string | undefined) {
  return useQuery({
    enabled: Boolean(graphId?.trim()),
    queryKey: ["mirofish-graph", graphId],
    queryFn: (): Promise<MirofishGraphPayload> =>
      fetchScenarioGraph(graphId?.trim() ?? ""),
  });
}

export async function queryScenarioSurreal(surrealSql: string) {
  return invoke<unknown>("query_scenario_surreal", { surrealSql });
}

export function useScenarioMirofishExperiments() {
  return useQuery({
    queryKey: ["scenario-mirofish-experiments"],
    queryFn: () => fetchScenarioMirofishExperiments(50),
    refetchInterval: 30_000,
  });
}

export function useScenarioMirofishExperimentDetail(
  experimentId: string | undefined,
) {
  return useQuery({
    enabled: Boolean(experimentId?.trim()),
    queryKey: ["scenario-mirofish-experiment", experimentId],
    queryFn: () =>
      fetchScenarioMirofishExperimentDetail(experimentId?.trim() ?? ""),
  });
}
