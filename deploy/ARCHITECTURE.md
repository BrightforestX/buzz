# Buzz + Ontology Stack Architecture

**Primary providers:** Fly.io (Buzz relay) + Railway (ontology API/UI + self-hosted Postgres/Redis).  
**Legacy:** DigitalOcean DOKS — see `ontology-stack/README.md` § Legacy DOKS.

## Placement decision: Postgres + Redis

| Component | Host | Why |
|-----------|------|-----|
| **Postgres** | Railway service (`postgres`) in ontology project | Same private network as linkml-stack / ontology-flow; no Neon lock-in; Buzz relay reaches it via Railway **TCP proxy** (TLS). |
| **Redis** | Railway service (`redis`) in ontology project | Pub/sub colocated with ontology; relay uses TCP proxy URL in Fly secrets. |
| **Buzz relay** | Fly Machines (`buzz-relay-pathx`) | Scale-to-zero compute; persistent git volume on Fly. |
| **linkml-stack** | Railway (Docker) | Surreal + Trino + MCP; **serverless** sleep when idle. |
| **ontology-flow** | Railway (Docker) | Next.js UI; **serverless** sleep when idle. |
| **Local workers** | Mac (harnesses, Baseten shim, Buzz desktop) | Started/stopped by `wake-stack.sh` / `sleep-stack.sh`. |

**Why not Fly Postgres/Redis?** Possible for colocation with relay, but splits state across two clouds, duplicates backup/ops, and ontology services on Railway would still need cross-cloud DB access. Keeping PG/Redis on Railway keeps one private mesh for ontology and a single TCP proxy surface for Fly.

**Why PG/Redis stay warm (not serverless):** Railway serverless on databases adds wake-on-connect latency and connection churn; relay migrations and pub/sub need stable TCP. App tiers (linkml-stack, ontology-flow) use serverless to save compute when Buzz is asleep.

## Connection patterns

### Inside Railway (private networking)

```
postgresql://buzz:${POSTGRES_PASSWORD}@postgres.railway.internal:5432/buzz
redis://default:${REDIS_PASSWORD}@redis.railway.internal:6379
```

linkml-stack talks to Surreal on localhost inside its container; ontology-flow uses `LINKML_STACK_URL=http://linkml-stack.railway.internal:8000` (set per service).

### Fly relay → self-hosted DB (public TCP proxy)

In Railway: enable **TCP Proxy** on `postgres` and `redis` services. Copy proxy host/port into Fly secrets:

```
# deploy/fly/secrets.env (never commit)
DATABASE_URL=postgresql://buzz:SECRET@containers-us-west-xxx.railway.app:PORT/buzz?sslmode=require
REDIS_URL=rediss://default:SECRET@containers-us-west-yyy.railway.app:PORT
```

Use `rediss://` when Railway Redis proxy supports TLS; otherwise `redis://` with proxy credentials. Prefer Railway-generated `${{Postgres.DATABASE_URL}}` for in-project services; use **public proxy URL** only on Fly.

## Lifecycle coordination

| State | Fly relay | Railway apps | Local Mac |
|-------|-----------|--------------|-----------|
| **Awake** | Machine running (or auto-start on traffic) | Woken by health pings in `wake-stack.sh` | Shim + harnesses up |
| **Sleeping** | Machines stopped (`sleep-stack.sh`) | Serverless idle (no keep-alive) | Workers stopped |

`STACK_AUTO_WAKE=1` (Buzz desktop) calls `wake-stack.sh`, which:

1. Ensures Postgres + Redis TCP (`wake-datastores.sh`; optional `STACK_DATASTORE_SLEEP=1`)
2. Pings ontology health URLs (`railway_stack_wake`)
3. Starts Fly relay (`fly_relay_wake`)
4. Starts local workers

**Stack wake proxy (optional):** `stack-lifecycle-proxy` on the Mac exposes stable local ports (`15432`/`16379`) that trigger `WakeDatastoreWorkflow` (Temporal) or `wake-datastores.sh` (shell) before forwarding to Railway TCP proxy URLs. Point Fly `DATABASE_URL`/`REDIS_URL` at the proxy when using cold datastore wake.

`STACK_PROVIDER=fly` only in current docs; `doks` remains in scripts for legacy teardown.

## Diagram

```mermaid
flowchart TB
  subgraph Internet
    Users[Browser / Buzz clients]
    CF[Cloudflare DNS + TLS]
  end

  subgraph Fly["Fly.io (iad)"]
    Relay[Buzz relay Machine\nauto_stop_machines]
    Vol[(buzz_git volume)]
    Relay --- Vol
  end

  subgraph Railway["Railway project: ontology-stack"]
    OF[ontology-flow\nserverless]
    LM[linkml-stack\nserverless]
    PG[(postgres\nalways on)]
    RD[(redis\nalways on)]
    OF --> LM
    OF -.->|private| LM
    Relay -->|TCP proxy TLS| PG
    Relay -->|TCP proxy TLS| RD
    LM --> PG
    OF --> PG
  end

  subgraph Local["Developer Mac"]
    Desktop[Buzz desktop]
    Shim[Baseten shim :8765]
    Harness[Agent harnesses x3]
    Wake[wake-stack.sh / sleep-stack.sh]
    Desktop --> Wake
    Wake --> Relay
    Wake --> OF
  end

  Users --> CF
  CF -->|relay.pathx.ai| Relay
  CF -->|ontology.pathx.ai| OF
  Desktop -->|WSS| Relay
```

## DNS (Cloudflare)

| Hostname | Target |
|----------|--------|
| `relay.pathx.ai` | CNAME → `<FLY_APP_NAME>.fly.dev` |
| `ontology.pathx.ai` | CNAME → Railway public domain for ontology-flow |
| `review.pathx.ai` | Optional; Railway solito-review or omit |

Remove DOKS cloudflared tunnel hostnames after cutover.

## Cost posture (idle)

| Resource | Idle cost |
|----------|-----------|
| Fly relay (stopped) | $0 compute; volume ~$0.15/GB/mo |
| Railway serverless apps | $0 when sleeping |
| Railway Postgres/Redis | Small always-on VM charge (cheaper than DOKS node pools) |
| Local Mac | $0 when sleeping |

## Related paths

- Fly relay: `deploy/fly/README.md`
- Railway ontology: `experiments/infrastructure/digitalocean/ontology-stack/deploy/railway/README.md`
- Lifecycle: `ontology-stack/scripts/wake-stack.sh`, `sleep-stack.sh`, `stack-status.sh`
