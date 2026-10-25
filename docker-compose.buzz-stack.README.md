# Buzz stack (Docker)

Single compose file for everything the **Scenarios** tab and MiroFish graph path hit on localhost.

## File

`docker-compose.buzz-stack.yml` — `docker-compose.scenarios.yml` is an **include alias** to this file.

## Services (default `up -d`)

| Service | Host port | Buzz / Tauri env |
|---------|-----------|------------------|
| trino | 8080 | `TRINO_HOST=http://127.0.0.1:8080` |
| surrealdb | 8001 | `SURREALDB_URL=http://127.0.0.1:8001`, user/pass `root`/`root` |
| neo4j | 7687, 7474 | (internal to zep-shim) |
| zep-shim | 8100 | MiroFish uses `ZEP_SHIM_BASE_URL` inside compose network |
| mirofish | 5001, 3000 | `MIROFISH_BASE_URL=http://127.0.0.1:5001` |

Surreal namespace/db for seeded PM issues: `SCENARIO_SURREAL_NS=sim`, `BUZZ_SCENARIO_SURREAL_DB=buzz_mirofish_scenario` (set in `run-buzz-desktop.sh`).

## Optional profiles

```bash
docker compose -f docker-compose.buzz-stack.yml --profile chain-graph up -d falkordb
docker compose -f docker-compose.buzz-stack.yml --profile chain-temporal up -d temporal
```

## Not in Docker (run on host)

| Port | Purpose |
|------|---------|
| 8765 | Baseten OpenAI shim — `./scripts/ensure-baseten-shim.sh` |
| 8766 | MiroFish chainlet — `BASETEN_CHAIN_ENDPOINT` in `MiroFish/.env` |
| 8081 | Optional OpenAPI Trino (Ontop) — `OPENAPI_TRINO_HOST` + separate pipeline |
| pathx | Buzz relay — `BUZZ_RELAY_URL` |

MiroFish container reaches host shims via `host.docker.internal:8765` / `:8766` when Baseten shims run locally. zep-shim uses `host.docker.internal:11434` for Ollama if installed.

## Commands

```bash
cd 01-platform/buzz
. ./bin/activate-hermit

# Up + wait + seed pm_issue into Surreal
./scripts/buzz-stack-up.sh

# Up + four Terminal log panes
./scripts/open-scenario-stack-panes.sh

# Down
docker compose -f docker-compose.buzz-stack.yml down
```

Then open Buzz → **Scenarios** or `#/scenarios?graphId=graph_mcp_eval_fixture`.
