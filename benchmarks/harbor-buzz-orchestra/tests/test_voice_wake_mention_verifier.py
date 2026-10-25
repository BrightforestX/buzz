import importlib.util
import json
from pathlib import Path

from harbor_buzz_orchestra.evidence import build_buzz_evidence
from harbor_buzz_orchestra.provisioning import AgentCredential, TrialHandle

DATASET_ROOT = Path(__file__).resolve().parents[2] / "buzz-dataset"
FIXTURES = Path(__file__).parent / "fixtures" / "transcripts"
VERIFIER = DATASET_ROOT / "voice-wake-mention" / "tests" / "verify.py"
SPEC = importlib.util.spec_from_file_location("voice_wake_mention_verifier", VERIFIER)
verifier = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(verifier)


def _credential(agent_id: str, role: str, pubkey: str) -> AgentCredential:
    return AgentCredential(
        agent_id=agent_id,
        role=role,
        nostr_secret_key="secret",
        nostr_pubkey=pubkey,
        nostr_auth_tag="auth",
        llm_endpoint="model" if role != "user" else "",
        llm_api_key="key" if role != "user" else "",
    )


def _evidence(root_content: str, reply_content: str) -> dict:
    transcript = json.loads((FIXTURES / "threaded.json").read_text(encoding="utf-8"))
    root, answer = transcript["messages"]
    root["content"] = root_content
    answer["content"] = reply_content
    trial = TrialHandle(
        run_id="run",
        trial_id="trial",
        manifest_hash="hash",
        relay_ws_url="ws://relay",
        channel_id=transcript["channel_id"],
        credentials=(_credential("solo-1", "orchestrator", answer["pubkey"]),),
        user=_credential("owner", "user", root["pubkey"]),
        task_name="voice-wake-mention",
    )
    return build_buzz_evidence(
        trial=trial,
        messages=transcript["messages"],
        task_event_id=root["id"],
        completion_message_id=None,
        transcript_limit=1000,
    )


def test_stripped_ingest_and_reply_passes():
    metrics, _ = verifier.score_evidence(
        _evidence("summarize the thread", "The thread covers deployment timing.")
    )
    assert metrics["content_has_no_wake_prefix"] == 1.0
    assert metrics["reward"] == 1.0


def test_wake_prefix_in_ingest_fails():
    metrics, _ = verifier.score_evidence(
        _evidence("tell buzz summarize the thread", "Done.")
    )
    assert metrics["content_has_no_wake_prefix"] == 0.0
    assert metrics["reward"] == 0.0
