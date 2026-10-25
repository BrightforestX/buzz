import assert from "node:assert/strict";
import test from "node:test";

import { parseMirofishGraphResponse } from "./mirofishGraphTypes.ts";

test("parseMirofishGraphResponse unwraps success payload", () => {
  const payload = parseMirofishGraphResponse({
    success: true,
    data: {
      nodes: [{ uuid: "n1", name: "Ada" }],
      edges: [{ source_uuid: "n1", target_uuid: "n2", name: "KNOWS" }],
    },
  });
  assert.equal(payload.nodes.length, 1);
  assert.equal(payload.edges.length, 1);
});

test("parseMirofishGraphResponse normalizes MiroFish edge uuid fields", () => {
  const payload = parseMirofishGraphResponse({
    success: true,
    data: {
      nodes: [
        { uuid: "n1", name: "Ada" },
        { uuid: "n2", name: "Grace" },
      ],
      edges: [
        {
          source_node_uuid: "n1",
          target_node_uuid: "n2",
          name: "REPORTS_TO",
        },
      ],
    },
  });
  assert.equal(payload.edges[0]?.source_uuid, "n1");
  assert.equal(payload.edges[0]?.target_uuid, "n2");
});

test("parseMirofishGraphResponse accepts zep-shim node list shape", () => {
  const payload = parseMirofishGraphResponse({
    success: true,
    data: {
      nodes: [{ uuid_: "abc", name: "Ada", labels: ["Engineer"] }],
      edges: [],
    },
  });
  assert.equal(payload.nodes[0]?.uuid, "abc");
});

test("parseMirofishGraphResponse tolerates missing data", () => {
  const payload = parseMirofishGraphResponse({ success: false });
  assert.deepEqual(payload, { nodes: [], edges: [] });
});
