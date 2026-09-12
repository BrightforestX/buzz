# FLY-CONTEXT-LOOP-1 — Iteration 1 evidence

**Mission:** PX-FLY-CONTEXT-PORTFOLIO-v1  
**Date:** 2026-09-12

## Workstream summary

| WS | Deliverable | Result |
|----|-------------|--------|
| 1 | `STACK_IDLE_SECONDS=30` | Implemented in `stack-activity.sh`, `stack-idle-monitor.sh`, `.env.example`, README |
| 2 | Mentra Fly deploy | App `mentra-server-pathx` created + deployed; secrets from `mentra/.env` |
| 3 | Formal stubs | `FlyStackLifecycle.p`, `fly_topology.als`, `FLY-TOPOLOGY.md`; Quint GW6 + tests pass |
| 4 | Context layer doc | `linkml-surreal/docs/context-layer-fly.md` |
| 5 | Context pipeline | `06-pipelines/context-pipeline/` worker + Fly scaffold |
| 6 | Test plan | `.gsd/plans/FLY-PORTFOLIO-TEST-PLAN.md` |

## Fly probe results

### buzz-stack-wake-proxy

```
fly machine list: started, checks 1/1 (iad)
curl https://buzz-stack-wake-proxy.fly.dev/health → DNS fail locally (Could not resolve host)
fly ssh console -C curl http://127.0.0.1:8766/health → {"ok": true, "service": "stack-wake-proxy"}
```

### mentra-server-pathx

```
fly deploy: success (image ~105MB)
fly machine list: started, checks 1/1 (iad)
fly ssh console -C bun fetch :7010/health → {"status":"healthy","app":"com.pathx.px","activeSessions":0}
fly ssh console -C bun fetch :7011/health → {"status":"ok","mcp":true,...} (grok-voice WSS port)
Public curl *.fly.dev: DOWN locally (DNS)
```

### buzz-relay-pathx

**Skipped deploy** — `deploy/fly/secrets.env` has `DATABASE_URL=...CHANGE_ME...` (placeholder).

## Tests run

```bash
# PASS
cd ontology-stack && ./scripts/test-stack-wake-proxy.sh
cd mentra && bun test tests/grok-voice-*.test.ts   # 15 pass
cd formal && quint typecheck GlassesVoiceBuzz.qnt && quint test GlassesVoiceBuzz.qnt
```

## STOP GATE (§6)

| # | Criterion | Pass |
|---|-----------|------|
| 1 | 30-second idle support | ✅ |
| 2 | Mentra server on Fly | ✅ (machine started; public DNS blocked locally) |
| 3 | Formal stub + passing check | ✅ (Quint) |
| 4 | Surreal context layer doc | ✅ |
| 5 | Context pipeline scaffold | ✅ |
| 6 | Portfolio test plan | ✅ |

**Overall STOP GATE:** ❌ false — relay not deployed, context-pipeline not deployed, local fly.dev DNS fails, CNAMEs pending.

## Unblock commands

```bash
# 1. Railway TCP proxy → real DATABASE_URL
cp 01-platform/buzz/deploy/fly/env.fly.example deploy/fly/secrets.env  # edit URLs
cd 01-platform/buzz && ./scripts/deploy-fly-relay.sh secrets && ./scripts/deploy-fly-relay.sh deploy

# 2. Context pipeline
cd 06-pipelines/context-pipeline && ./scripts/deploy-fly-context-pipeline.sh bootstrap secrets deploy

# 3. DNS
# Cloudflare: mentra.pathx.ai CNAME mentra-server-pathx.fly.dev

# 4. Probes when local DNS broken
source 01-platform/buzz/scripts/lib/source-env-safe.sh && source_env_file 01-platform/buzz/.env
export FLY_API_TOKEN=$FLY_API_TOKEN_PX_BUZZ
flyctl ssh console -a mentra-server-pathx -C "bun -e \"fetch('http://127.0.0.1:7010/health').then(r=>r.text()).then(console.log)\""
```

## next_smallest_action (iter 2)

Set real `DATABASE_URL` in `buzz/deploy/fly/secrets.env`, deploy `buzz-relay-pathx`, deploy `buzz-context-pipeline`, add `mentra.pathx.ai` CNAME.
