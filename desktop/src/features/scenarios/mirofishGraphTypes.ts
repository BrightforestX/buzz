export type MirofishGraphNode = {
  uuid: string;
  uuid_?: string;
  name?: string;
  labels?: string[];
  summary?: string;
  attributes?: Record<string, unknown>;
  created_at?: string;
};

function normalizeNode(node: MirofishGraphNode): MirofishGraphNode {
  const uuid = node.uuid ?? node.uuid_ ?? "";
  return { ...node, uuid };
}

export type MirofishGraphEdge = {
  uuid?: string;
  source_uuid?: string;
  target_uuid?: string;
  source_node_uuid?: string;
  target_node_uuid?: string;
  source_name?: string;
  target_name?: string;
  source_node_name?: string;
  target_node_name?: string;
  name?: string;
  fact?: string;
};

function normalizeEdge(edge: MirofishGraphEdge): MirofishGraphEdge {
  return {
    ...edge,
    source_uuid: edge.source_uuid ?? edge.source_node_uuid,
    target_uuid: edge.target_uuid ?? edge.target_node_uuid,
    source_name: edge.source_name ?? edge.source_node_name,
    target_name: edge.target_name ?? edge.target_node_name,
  };
}

export type MirofishGraphPayload = {
  nodes: MirofishGraphNode[];
  edges: MirofishGraphEdge[];
};

export function parseMirofishGraphResponse(
  body: unknown,
): MirofishGraphPayload {
  if (!body || typeof body !== "object") {
    return { nodes: [], edges: [] };
  }
  const record = body as Record<string, unknown>;
  const data =
    record.data && typeof record.data === "object"
      ? (record.data as Record<string, unknown>)
      : record;
  const rawNodes = Array.isArray(data.nodes)
    ? (data.nodes as MirofishGraphNode[])
    : [];
  const nodes = rawNodes
    .map(normalizeNode)
    .filter((node) => node.uuid.length > 0);
  const rawEdges = Array.isArray(data.edges)
    ? (data.edges as MirofishGraphEdge[])
    : [];
  const edges = rawEdges.map(normalizeEdge);
  return { nodes, edges };
}
