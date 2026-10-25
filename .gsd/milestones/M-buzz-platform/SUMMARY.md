# M-buzz-platform SUMMARY — evidence index

| Date | Slice | Evidence file |
|------|-------|---------------|
| 2026-09-08 | Phase 0 | `.gsd/evidence/20260908-buzz-platform-phase0.md` |
| 2026-09-08 | S01 | `.gsd/evidence/20260908-buzz-s01.md` |
| 2026-09-08 | S02 | `.gsd/evidence/20260908-buzz-s02.md` |
| 2026-09-08 | S03 | `.gsd/evidence/20260908-buzz-s03.md` |
| 2026-09-08 | S04 | `.gsd/evidence/20260908-buzz-s04.md` |
| 2026-09-08 | S05 | `.gsd/evidence/20260908-buzz-s05.md` |
| 2026-09-08 | S06 / rollup | `.gsd/evidence/20260908-buzz-platform-e2e.md` |

## Gate runs

| Gate | Last run | Result |
|------|----------|--------|
| Phase 0 checklist | 2026-09-08 | PASS |
| S01 agentConfigCore | 2026-09-08 | 30/30 PASS |
| S02 smoke-daytona-operator | 2026-09-08 | **PASS (dry-run)** |
| S02 agentAccessWarning | 2026-09-08 | 8/8 PASS |
| S03 `cargo test baseten` | 2026-09-08 | **BLOCKED** — opus linker |
| S04 smoke-platform-loop | 2026-09-08 | **PASS** |
| S05 `cargo test -p buzz-workflow` | 2026-09-08 | **PASS** (169 tests) |
| S06 smoke-platform-loop | 2026-09-08 | **PASS** |
| S06 smoke-daytona | 2026-09-08 | **PASS (dry-run)** |
| S06 cloud-agent smoke:formal | 2026-09-08 | **PARTIAL** (19 pass, 1 fail) |
| S06 platform keys | 2026-09-08 | **UNSET** — no live loop |
| `just ci` | — | not run |

## Manifest

| Row | Status |
|-----|--------|
| `PRODUCT-B-buzz-durable-agent-platform` | open (docs gate met) |
| `PRODUCT-B-agent-dispatch` | covered |
| `PRODUCT-B-daytona-do` | covered |
| `PRODUCT-B-baseten-think` | open (deferred: linker) |
| `PRODUCT-B-formal-hooks` | **covered** |
| `PRODUCT-B-temporal-handoff` | open (deferred: 010 T052) |

## Milestone

**M-buzz-platform** — docs-complete S01–S06; integration manifest open pending wire follow-up.
