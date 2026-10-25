import { invoke } from "@tauri-apps/api/core";

import {
  parseMirofishGraphResponse,
  type MirofishGraphPayload,
} from "@/features/scenarios/mirofishGraphTypes";

const DEFAULT_ZEP_SHIM_BASE = "http://127.0.0.1:8100/api/v2";

function zepShimBaseUrl(): string {
  return (
    (import.meta.env.VITE_ZEP_SHIM_BASE_URL as string | undefined)?.trim() ||
    DEFAULT_ZEP_SHIM_BASE
  ).replace(/\/$/, "");
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  if (typeof error === "string") {
    return error;
  }
  return "Graph load failed";
}

async function fetchGraphFromZepShim(
  graphId: string,
): Promise<MirofishGraphPayload> {
  const base = zepShimBaseUrl();
  const listBody = JSON.stringify({ limit: 500 });
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  const nodesRes = await fetch(
    `${base}/graph/node/graph/${encodeURIComponent(graphId)}`,
    {
      method: "POST",
      headers,
      body: listBody,
    },
  );
  if (!nodesRes.ok) {
    throw new Error(`zep-shim nodes HTTP ${nodesRes.status}`);
  }
  const nodesRaw = (await nodesRes.json()) as unknown;
  const edgesRes = await fetch(
    `${base}/graph/edge/graph/${encodeURIComponent(graphId)}`,
    {
      method: "POST",
      headers,
      body: listBody,
    },
  );
  const edgesRaw = edgesRes.ok ? await edgesRes.json() : [];
  return parseMirofishGraphResponse({
    success: true,
    data: {
      graph_id: graphId,
      nodes: Array.isArray(nodesRaw) ? nodesRaw : [],
      edges: Array.isArray(edgesRaw) ? edgesRaw : [],
    },
  });
}

/** Load scenario graph via Tauri (MiroFish → zep in Rust), then direct zep-shim if needed. */
export async function fetchScenarioGraph(
  graphId: string,
): Promise<MirofishGraphPayload> {
  const id = graphId.trim();
  if (!id) {
    throw new Error("graphId is required");
  }

  let invokeError: unknown;
  try {
    const body = await invoke<unknown>("fetch_mirofish_graph_data", {
      graphId: id,
    });
    const parsed = parseMirofishGraphResponse(body);
    if (parsed.nodes.length > 0) {
      return parsed;
    }
  } catch (error) {
    invokeError = error;
  }

  try {
    const fromZep = await fetchGraphFromZepShim(id);
    if (fromZep.nodes.length > 0) {
      return fromZep;
    }
  } catch (zepError) {
    const tail = errorMessage(zepError);
    if (invokeError !== undefined) {
      throw new Error(`${errorMessage(invokeError)} (zep-shim: ${tail})`);
    }
    throw zepError instanceof Error ? zepError : new Error(tail);
  }

  if (invokeError !== undefined) {
    throw invokeError instanceof Error
      ? invokeError
      : new Error(errorMessage(invokeError));
  }
  throw new Error(
    "Graph has no nodes — run scripts/seed-mirofish-graph-fixture.py",
  );
}

export { errorMessage as scenarioGraphErrorMessage };
