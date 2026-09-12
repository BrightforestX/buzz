# Buzz relay on Fly + Railway Postgres/Redis

Production relay for `wss://relay.pathx.ai`. Split state:

| Layer | Provider | Idle cost |
|-------|----------|-----------|
| Relay compute | Fly Machine | **$0** when stopped (`auto_stop_machines = stop`) |
| Git repos | Fly volume `buzz_git` | ~$0.15/GB/mo (volume only) |
| Postgres | Railway (self-hosted) | Always-on; TCP proxy for Fly |
| Redis pub/sub | Railway (self-hosted) | Always-on; TCP proxy for Fly |
| Ontology UI/API | Railway serverless | $0 when sleeping |
| Media | Tigris / R2 / S3 | Usage-based |

Stopped Fly machine = no compute bill. Volume and Railway PG/Redis persist.

See `deploy/ARCHITECTURE.md` for full topology.

## Prerequisites

- `flyctl auth login`
- Railway project with Postgres + Redis + TCP proxy enabled (`ontology-stack/deploy/railway/README.md`)
- `DATABASE_URL` and `REDIS_URL` pointing at **Railway TCP proxy** endpoints (TLS)
- S3-compatible bucket (Fly Tigris: `fly storage create`)
- Secrets from `experiments/01-platform/buzz/.env` (`BUZZ_RELAY_PRIVATE_KEY`, etc.)

## One-time bootstrap

```bash
cd experiments/01-platform/buzz
export FLY_APP_NAME=buzz-relay-pathx   # optional override

# 1. App + volume
fly apps create "$FLY_APP_NAME" --org personal   # skip if exists
fly volumes create buzz_git --size 10 --region iad -a "$FLY_APP_NAME"

# 2. Secrets (never commit secrets.env)
cp deploy/fly/env.fly.example deploy/fly/secrets.env
# edit deploy/fly/secrets.env — Railway TCP proxy URLs for DATABASE_URL / REDIS_URL
fly secrets import < deploy/fly/secrets.env -a "$FLY_APP_NAME"

# 3. Preflight (Railway auth, non-placeholder DATABASE_URL/REDIS_URL in secrets.env, Fly auth, TLS)
./scripts/deploy-preflight.sh

# 4. Deploy
./scripts/deploy-fly-relay.sh deploy

# 5. Custom domain
fly certs create relay.pathx.ai -a "$FLY_APP_NAME"
fly certs setup relay.pathx.ai -a "$FLY_APP_NAME"   # shows A/AAAA or CNAME targets

# Cloudflare (proxied orange-cloud is OK):
#   CNAME relay → <app-hostname>.fly.dev
#   TXT _fly-ownership.relay → app-<hostname>   # required behind CDN/proxy
# Verify: fly certs check relay.pathx.ai -a "$FLY_APP_NAME"
```

## Fly relay → Railway DB

Railway services use private DNS inside the project (`postgres.railway.internal`). Fly cannot reach private networking — use **TCP Proxy** on Postgres and Redis in Railway Dashboard:

1. Railway → `postgres` → Networking → TCP Proxy → copy host:port
2. Railway → `redis` → Networking → TCP Proxy → copy host:port
3. Set in `deploy/fly/secrets.env`:

```
DATABASE_URL=postgresql://buzz:PASSWORD@tcp-proxy-host:PORT/buzz?sslmode=require
REDIS_URL=rediss://default:PASSWORD@tcp-proxy-host:PORT
```

Use Railway-generated credentials from the plugin variables. Rotate via Railway; update Fly secrets with `fly secrets import`.

**Security:** TCP proxy is authenticated (password in URL). Do not expose raw Postgres without proxy. Tailscale is optional; TCP proxy is the default path.

## Day-2 operations

```bash
./scripts/deploy-fly-relay.sh status   # machine + relay probe
./scripts/deploy-fly-relay.sh wake     # start stopped machine(s)
./scripts/deploy-fly-relay.sh sleep    # stop machines (no compute)
./scripts/deploy-fly-relay.sh deploy   # new image / config
```

Stack lifecycle (`wake-stack.sh` / `sleep-stack.sh`) uses these when `STACK_PROVIDER=fly` (default). Wake also pings Railway ontology health URLs.

## Scale-to-zero behavior

- **Auto:** Fly stops the machine after idle HTTP traffic (`auto_stop_machines = stop`).
- **Manual:** `sleep-stack.sh` or `deploy-fly-relay.sh sleep` stops all machines immediately.
- **Wake:** First HTTPS/WSS request to `relay.pathx.ai` auto-starts the machine (~5–15s cold start), or run `wake-stack.sh`.

## Migrating from DOKS / Neon / Upstash

1. Export git data from old cluster PVC if needed.
2. Bootstrap Railway Postgres/Redis + Fly relay; run migrations via `BUZZ_AUTO_MIGRATE=true`.
3. Point `relay.pathx.ai` DNS to Fly; verify `curl -fsS https://relay.pathx.ai/_readiness`.
4. Destroy remaining DigitalOcean resources:

```bash
cd experiments/infrastructure/digitalocean/ontology-stack
STACK_DESTROY_DO_CONFIRM=1 ./scripts/destroy-do-stack.sh
```

## Cost notes

- Fly volume billed while attached even when machine is stopped.
- Railway Postgres/Redis: small always-on charge (cheaper than DOKS node pools).
- Railway app services: serverless = $0 when idle.
