# voice-wake-mention

Harbor regression task for the glasses voice → Buzz bridge: the human's kind:9
**content** must be wake-stripped (as Mentra publishes), include an agent `p` tag, and
the agent reply must not echo wake prefixes.

Verifier highlights:

- `user_p_tagged` — ingest event tags the agent pubkey
- `content_has_no_wake_prefix` — neither ingest nor reply contains `tell buzz` / `hey …` prefixes
- `same_channel` / `expected_author` — standard Buzz-native checks

Run via existing `just benchmark` / Harbor orchestra with path
`benchmarks/buzz-dataset/voice-wake-mention`.
