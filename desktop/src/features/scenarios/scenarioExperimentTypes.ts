export type ScenarioMirofishExperimentRow = {
  experimentId: string;
  title?: string | null;
  status?: string | null;
  projectId?: string | null;
  graphId?: string | null;
  simulationId?: string | null;
  reportId?: string | null;
  updatedAt?: string | null;
};

export type ScenarioMirofishExperimentDetail = {
  experiment: ScenarioMirofishExperimentRow;
  results?: unknown;
};

export function reportSummaryFromResults(results: unknown): string | null {
  if (!results || typeof results !== "object") {
    return null;
  }
  const report = (results as Record<string, unknown>).report;
  if (!report || typeof report !== "object") {
    return null;
  }
  const record = report as Record<string, unknown>;
  for (const key of [
    "summary",
    "title",
    "name",
    "content",
    "executive_summary",
  ]) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}
