import { invoke } from "@tauri-apps/api/core";

import type {
  ScenarioMirofishExperimentDetail,
  ScenarioMirofishExperimentRow,
} from "@/features/scenarios/scenarioExperimentTypes";
import { waitForTauriIpcReady } from "@/shared/lib/tauriReady";

const DEFAULT_SURREAL_URL = "http://127.0.0.1:8001";
const DEFAULT_SURREAL_NS = "sim";
const DEFAULT_EXPERIMENT_DB = "mirofish_experiments_v2";

function surrealUrl(): string {
  return (
    (import.meta.env.VITE_SURREALDB_URL as string | undefined)?.trim() ||
    DEFAULT_SURREAL_URL
  ).replace(/\/$/, "");
}

function experimentDb(): string {
  return (
    (
      import.meta.env.VITE_MIROFISH_EXPERIMENT_DB as string | undefined
    )?.trim() || DEFAULT_EXPERIMENT_DB
  );
}

function surrealNs(): string {
  return (
    (import.meta.env.VITE_SCENARIO_SURREAL_NS as string | undefined)?.trim() ||
    DEFAULT_SURREAL_NS
  );
}

export function isUnknownTauriCommandError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /not found|unknown command|Command .+ not found/i.test(message);
}

export const STALE_BUZZ_DESKTOP_HINT =
  "Restart Buzz Desktop so it picks up the latest Scenarios commands (quit the app, then run ./scripts/run-buzz-desktop.sh).";

function parseSurrealRows(body: unknown): Record<string, unknown>[] {
  if (!Array.isArray(body)) {
    return [];
  }
  const rows: Record<string, unknown>[] = [];
  for (const block of body) {
    if (!block || typeof block !== "object") {
      continue;
    }
    const record = block as Record<string, unknown>;
    if (record.status === "ERR") {
      throw new Error(String(record.result ?? "SurrealDB SQL error"));
    }
    const result = record.result;
    if (!Array.isArray(result)) {
      continue;
    }
    for (const item of result) {
      if (item && typeof item === "object") {
        rows.push(item as Record<string, unknown>);
      }
    }
  }
  return rows;
}

async function postSurrealSql(sql: string, database: string): Promise<unknown> {
  const url = `${surrealUrl()}/sql`;
  const auth = btoa("root:root");
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "text/plain",
      Authorization: `Basic ${auth}`,
      "surreal-ns": surrealNs(),
      "surreal-db": database,
    },
    body: sql,
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`SurrealDB HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  return response.json();
}

function rowToExperiment(
  row: Record<string, unknown>,
): ScenarioMirofishExperimentRow | null {
  const experimentId = String(row.experiment_id ?? "").trim();
  if (!experimentId) {
    return null;
  }
  const pick = (key: string): string | null => {
    const value = row[key];
    return typeof value === "string" && value.trim() ? value.trim() : null;
  };
  return {
    experimentId,
    title: pick("title"),
    status: pick("status"),
    projectId: pick("project_id"),
    graphId: pick("graph_id"),
    simulationId: pick("simulation_id"),
    reportId: pick("report_id"),
    updatedAt: pick("updated_at"),
  };
}

async function listExperimentsFromSurreal(
  limit: number,
): Promise<ScenarioMirofishExperimentRow[]> {
  const sql = `SELECT experiment_id, title, status, project_id, graph_id, simulation_id, report_id, updated_at FROM mirofish_experiment ORDER BY updated_at DESC LIMIT ${limit};`;
  const body = await postSurrealSql(sql, experimentDb());
  return parseSurrealRows(body)
    .map(rowToExperiment)
    .filter((row): row is ScenarioMirofishExperimentRow => row !== null);
}

async function getExperimentFromSurreal(
  experimentId: string,
): Promise<ScenarioMirofishExperimentDetail> {
  if (!/^[a-zA-Z0-9_-]+$/.test(experimentId)) {
    throw new Error("Invalid experiment id");
  }
  const sql = `SELECT experiment_id, title, status, project_id, graph_id, simulation_id, report_id, updated_at, results_json FROM mirofish_experiment WHERE experiment_id = '${experimentId}' LIMIT 1;`;
  const body = await postSurrealSql(sql, experimentDb());
  const row = parseSurrealRows(body)[0];
  if (!row) {
    throw new Error(`experiment not found: ${experimentId}`);
  }
  const experiment = rowToExperiment(row);
  if (!experiment) {
    throw new Error(`invalid experiment row: ${experimentId}`);
  }
  let results: unknown;
  const raw = row.results_json;
  if (typeof raw === "string" && raw.trim()) {
    try {
      results = JSON.parse(raw) as unknown;
    } catch {
      results = undefined;
    }
  } else if (raw && typeof raw === "object") {
    results = raw;
  }
  return { experiment, results };
}

export async function fetchScenarioMirofishExperiments(
  limit = 50,
): Promise<ScenarioMirofishExperimentRow[]> {
  if (await waitForTauriIpcReady(2_000)) {
    try {
      return await invoke<ScenarioMirofishExperimentRow[]>(
        "list_scenario_mirofish_experiments",
        {
          limit,
        },
      );
    } catch (error) {
      if (!isUnknownTauriCommandError(error)) {
        throw error;
      }
    }
  }
  return listExperimentsFromSurreal(limit);
}

export async function fetchScenarioMirofishExperimentDetail(
  experimentId: string,
): Promise<ScenarioMirofishExperimentDetail> {
  const id = experimentId.trim();
  if (await waitForTauriIpcReady(2_000)) {
    try {
      return await invoke<ScenarioMirofishExperimentDetail>(
        "get_scenario_mirofish_experiment",
        {
          experimentId: id,
        },
      );
    } catch (error) {
      if (!isUnknownTauriCommandError(error)) {
        throw error;
      }
    }
  }
  return getExperimentFromSurreal(id);
}

export async function runScenarioMirofishExperimentFixture(): Promise<unknown> {
  if (!(await waitForTauriIpcReady(5_000))) {
    throw new Error(
      `${STALE_BUZZ_DESKTOP_HINT} Or run: baseten-chain-mcp/scripts/buzz-scenario-orchestrated-run.py`,
    );
  }
  try {
    return await invoke("run_scenario_mirofish_experiment_fixture");
  } catch (error) {
    if (isUnknownTauriCommandError(error)) {
      throw new Error(STALE_BUZZ_DESKTOP_HINT);
    }
    throw error;
  }
}

export type CustomerScenarioFleetResult = {
  report_path?: string;
  catalog_size?: number;
  passed?: number;
  failed?: number;
  scenarios?: Array<{
    ok?: boolean;
    scenario_key?: string;
    engine?: string;
    graph_id?: string;
    experiment_id?: string;
    error?: string;
  }>;
};

export async function runCustomerScenarioFleet(): Promise<CustomerScenarioFleetResult> {
  if (!(await waitForTauriIpcReady(5_000))) {
    throw new Error(
      `${STALE_BUZZ_DESKTOP_HINT} Or run: ./scripts/buzz-customer-scenario-container.sh`,
    );
  }
  try {
    return await invoke<CustomerScenarioFleetResult>(
      "run_customer_scenario_fleet",
    );
  } catch (error) {
    if (isUnknownTauriCommandError(error)) {
      throw new Error(STALE_BUZZ_DESKTOP_HINT);
    }
    throw error;
  }
}
