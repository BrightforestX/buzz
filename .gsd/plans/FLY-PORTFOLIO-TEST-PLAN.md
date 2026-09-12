# FLY portfolio test plan — PX-FLY-CONTEXT-PORTFOLIO-v1

**Iteration:** 1  
**Evidence:** `.gsd/evidence/FLY-CONTEXT-LOOP-1.md`

## Forks (≥3)

### 1. buzz-relay-pathx (base)

| Field | Value |
|-------|-------|
| Fly app | `buzz-relay-pathx` |
| Public URL | `https://relay.pathx.ai` (CNAME → fly.dev) |
| E2E | `cd experiments/01-platform/buzz && ./scripts/test-agents-and-relay.sh --ping` |
| Surreal tenant prefix | `tenant:fly:buzz-relay` |
| Deploy | `./scripts/deploy-fly-relay.sh deploy` (requires real `DATABASE_URL` in secrets) |

### 2. mentra-server-pathx

| Field | Value |
|-------|-------|
| Fly app | `mentra-server-pathx` |
| Public URL | `https://mentra-server-pathx.fly.dev` (target `mentra.pathx.ai`) |
| E2E | `cd experiments/02-products/glasses/mentra && bun test tests/grok-voice-*.test.ts` |
| WSS probe | `wscat -c wss://mentra-server-pathx.fly.dev/api/grok-voice` (after deploy) |
| Surreal tenant prefix | `tenant:fly:mentra` |
| Deploy | `./scripts/deploy-fly-mentra.sh bootstrap && stage && secrets && deploy` |

### 3. buzz-stack-wake-proxy

| Field | Value |
|-------|-------|
| Fly app | `buzz-stack-wake-proxy` |
| Public URL | `https://buzz-stack-wake-proxy.fly.dev/health` |
| E2E | `cd experiments/infrastructure/digitalocean/ontology-stack && ./scripts/test-stack-wake-proxy.sh` |
| Surreal tenant prefix | `tenant:fly:wake-proxy` |
| Deploy | `./scripts/deploy-fly-stack-wake-proxy.sh deploy` |

### 4. (optional) buzz-context-pipeline

| Field | Value |
|-------|-------|
| Fly app | `buzz-context-pipeline` |
| E2E | `curl -fsS https://buzz-context-pipeline.fly.dev/health` |
| Ingest | `curl -X POST .../ingest -d '{"fork_id":"buzz-relay-pathx","kind":"AgentTurn"}'` |
| Surreal tenant prefix | `tenant:fly:context` |

## Cross-fork gates

- [formal-gates.md](../specs/011-buzz-durable-agent-platform/contracts/formal-gates.md) — px-validate before validated writes
- `06-pipelines/formal/GlassesVoiceBuzz.qnt` — voice buzz invariants
- `STACK_IDLE_SECONDS=30` — idle sleep experiment (WS-1)

## STOP GATE checklist (§6)

See `.gsd/evidence/FLY-CONTEXT-LOOP-STATE.yaml` → `stop_gate`.
