# PX-FLY-CONTEXT Loop 2 — Follow-up (2026-09-12)

## Actions taken

1. Verified Fly apps via `fly status`:
   - `mentra-server-pathx` — started, 1/1 checks
   - `buzz-stack-wake-proxy` — started, 1/1 checks
   - `buzz-relay-pathx` — no image (not deployed)

2. In-machine Mentra health (local `*.fly.dev` DNS fails):
   ```json
   {"status":"healthy","app":"com.pathx.px","activeSessions":0}
   ```

3. `buzz-context-pipeline` bootstrap + deploy attempted:
   - App created; machine crash loop: `Module not found "src/worker.ts"`
   - Root cause: Dockerfile `COPY package.json src/ ./` flattened `src/` into `/app/`
   - Fix applied: preserve `src/` layout in `deploy/fly/Dockerfile`
   - Redeployed; health check **passing**:
     ```json
     {"status":"ok","app":"buzz-context-pipeline","surrealWrite":false}
     ```

## Still blocked (user action)

| Blocker | Action |
|---------|--------|
| `buzz-relay-pathx` | Real `DATABASE_URL` / `REDIS_URL` in `buzz/deploy/fly/secrets.env` |
| `mentra.pathx.ai` | Cloudflare CNAME → `mentra-server-pathx.fly.dev` |
| Local DNS | `*.fly.dev` resolution fails; use `fly ssh console` probes |

## STOP GATE

**passed:** false — relay not live; portfolio E2E pending.
