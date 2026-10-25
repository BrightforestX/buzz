#!/usr/bin/env python3
"""
Seed graph_mcp_eval_fixture into zep-shim (Graphiti + Neo4j) for Buzz Scenarios + green/red.

Requires zep-shim (:8100) and a local LLM at ZEP_SHIM_LLM_BASE_URL (Ollama on :11434 by default).
Idempotent: skips ingest when MiroFish already returns nodes for the fixture graph.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

GRAPH_ID = os.environ.get("MIROFISH_FIXTURE_GRAPH_ID", "graph_mcp_eval_fixture")
MIROFISH_BASE = os.environ.get("MIROFISH_BASE_URL", "http://127.0.0.1:5001").rstrip("/")
ZEP_BASE = os.environ.get("ZEP_SHIM_BASE_URL", "http://127.0.0.1:8100/api/v2").rstrip("/")

EPISODES = [
    "Ada is an engineer on the Platform team. Ada reports to Grace.",
    "Kofi is an engineer on the Platform team. Kofi reports to Grace.",
    "Grace is a manager who leads the Platform team.",
]

ONTOLOGY = {
    "graph_ids": [GRAPH_ID],
    "entity_types": [
        {"name": "Engineer", "description": "Individual contributor"},
        {"name": "Manager", "description": "Team lead"},
        {"name": "Team", "description": "Engineering team"},
    ],
    "edge_types": [
        {"name": "REPORTS_TO", "description": "Reports to manager"},
        {"name": "MEMBER_OF", "description": "Member of team"},
    ],
}


def http_json(method: str, url: str, body: dict | None = None, timeout: float = 120.0) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw.strip() else {}


def mirofish_has_nodes() -> bool:
    try:
        payload = http_json("GET", f"{MIROFISH_BASE}/api/graph/data/{GRAPH_ID}", timeout=20.0)
    except urllib.error.HTTPError:
        payload = None
    except OSError:
        payload = None
    if isinstance(payload, dict) and payload.get("success") is not False:
        data = payload.get("data")
        nodes = data.get("nodes") if isinstance(data, dict) else None
        if isinstance(nodes, list) and len(nodes) > 0:
            return True
    try:
        zep_nodes = http_json(
            "POST",
            f"{ZEP_BASE}/graph/node/graph/{GRAPH_ID}",
            {"limit": 1},
            timeout=20.0,
        )
    except (urllib.error.HTTPError, OSError):
        return False
    return isinstance(zep_nodes, list) and len(zep_nodes) > 0


def seed_zep() -> dict:
    http_json("POST", f"{ZEP_BASE}/graph/create", {"graph_id": GRAPH_ID, "name": "mcp eval fixture"})
    http_json("PUT", f"{ZEP_BASE}/entity-types", ONTOLOGY)
    ingested = []
    for text in EPISODES:
        result = http_json(
            "POST",
            f"{ZEP_BASE}/graph",
            {"graph_id": GRAPH_ID, "type": "text", "data": text},
            timeout=300.0,
        )
        ingested.append(result.get("uuid_") or "ok")
    return {"episodes": len(ingested)}


def main() -> int:
    if mirofish_has_nodes():
        print(json.dumps({"graph_id": GRAPH_ID, "seeded": False, "reason": "nodes already present"}))
        return 0
    try:
        summary = seed_zep()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(json.dumps({"ok": False, "error": f"zep HTTP {exc.code}", "body": body[:500]}))
        return 1
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1

    if not mirofish_has_nodes():
        print(
            json.dumps(
                {
                    "ok": False,
                    "graph_id": GRAPH_ID,
                    "zep": summary,
                    "hint": "zep ingest ran but MiroFish still has no nodes — check Ollama/embeddings",
                }
            )
        )
        return 1

    print(json.dumps({"ok": True, "graph_id": GRAPH_ID, "seeded": True, "zep": summary}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
