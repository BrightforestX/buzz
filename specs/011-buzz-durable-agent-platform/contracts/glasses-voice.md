# Contract: Glasses voice → Buzz agents

**Spec:** [011-buzz-durable-agent-platform](../spec.md)  
**Mentra contract:** [voice-buzz-bridge.md](../../../../02-products/glasses/mentra/docs/voice-buzz-bridge.md)

## Buzz-side obligations

1. **Wake-only ingest:** Only kind:9 events whose content does not include a wake prefix in the relay copy (content is already stripped by Mentra before publish).

2. **Mention gate:** Agent harness wakes on `p` tag = agent pubkey ([`event_mentions_agent`](../../../../crates/buzz-acp/src/lib.rs)). Mentra MUST include `p`.

3. **Owner-only:** Default `--respond-to owner-only` applies. Events MUST be signed with the **owner** pubkey via NIP-46 bunker, not a bridge key.

4. **Channel membership:** Agent and owner MUST be members of `h` channel before the turn.

5. **Reply:** Agent replies with kind:9 in the same channel. Glasses consume `content` for TTS.

## Desktop NIP-46 bunker

- Crate: `buzz-nip46` (protocol) + Tauri commands `nip46_*`
- Allowlist client pubkeys after user approval
- Sign kinds `{9, 22242}` only

## Formal invariants (Quint)

| ID | Claim |
|----|-------|
| G-W1 | `publish` only after `wakeMatch` |
| G-W2 | Mentra state never contains owner `nsec` |
| G-W3 | Bunker `sign_event` kinds ⊆ `{9, 22242}` |
| G-W4 | Spoken reply only if author = agent, same `h`, and reply references ingest |
| G-W5 | Non-wake transcripts never change relay |

Model: `06-pipelines/formal/GlassesVoiceBuzz.qnt`

## Evals

- Harbor: `benchmarks/buzz-dataset/voice-wake-mention`
- Mentra: `mentra/tests/voice-buzz-*.test.ts`

## Out of scope (v1)

- Changing `--respond-to` defaults
- NIP-PL push wake
- Grok tool-calling Buzz
