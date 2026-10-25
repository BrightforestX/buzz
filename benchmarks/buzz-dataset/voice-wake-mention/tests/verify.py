#!/usr/bin/env python3
"""Verifier for glasses voice wake → kind:9 mention (stripped content, agent reply)."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

WAKE_PREFIX = re.compile(
    r"^(?:tell|ask)\s+buzz\s+|hey\s+[a-z0-9][a-z0-9_-]{0,48}\s+|ask\s+[a-z0-9][a-z0-9_-]{0,48}\s+",
    re.IGNORECASE,
)


def _has_p_tag(message: dict[str, Any], pubkey: object) -> bool:
    return isinstance(pubkey, str) and any(
        isinstance(tag, list) and len(tag) >= 2 and tag[0] == "p" and tag[1] == pubkey
        for tag in message.get("tags", [])
    )


def _zero_metrics() -> dict[str, float]:
    return {
        "reward": 0.0,
        "user_p_tagged": 0.0,
        "same_channel": 0.0,
        "expected_author": 0.0,
        "content_has_no_wake_prefix": 0.0,
        "evidence_complete": 0.0,
    }


def content_has_no_wake_prefix(content: str) -> bool:
    normalized = content.strip().lower()
    if not normalized:
        return False
    return WAKE_PREFIX.search(normalized) is None


def score_evidence(evidence: object) -> tuple[dict[str, float], dict[str, Any]]:
    if not isinstance(evidence, dict):
        return _zero_metrics(), {"error": "evidence root is not an object"}

    task_event_id = evidence.get("task_event_id")
    trial = evidence.get("trial") if isinstance(evidence.get("trial"), dict) else {}
    channel_id = trial.get("channel_id")
    identities = (
        evidence.get("identities")
        if isinstance(evidence.get("identities"), dict)
        else {}
    )
    agents = [
        row
        for row in identities.values()
        if isinstance(row, dict) and row.get("role") == "orchestrator"
    ]
    agent_pubkey = agents[0].get("pubkey") if len(agents) == 1 else None
    messages = [
        message for message in evidence.get("messages", []) if isinstance(message, dict)
    ]
    root_indexes = [
        index
        for index, message in enumerate(messages)
        if message.get("id") == task_event_id
    ]
    root_index = root_indexes[0] if len(root_indexes) == 1 else -1
    root = messages[root_index] if root_index >= 0 else None
    candidates = [
        message
        for message in messages[root_index + 1 :]
        if agent_pubkey and message.get("pubkey") == agent_pubkey
    ]
    final = candidates[-1] if candidates else None
    root_content = str(root.get("content", "")) if root is not None else ""
    final_content = str(final.get("content", "")) if final is not None else ""

    evidence_complete = float(
        evidence.get("schema_version") == 1
        and evidence.get("task_name") == "voice-wake-mention"
        and evidence.get("truncated") is False
        and isinstance(task_event_id, str)
        and len(root_indexes) == 1
        and isinstance(channel_id, str)
        and len(agents) == 1
        and root is not None
        and final is not None
    )
    expected_author = float(final is not None and final.get("pubkey") == agent_pubkey)
    same_channel = float(
        final is not None
        and final.get("channel_id") == channel_id
        and ["h", channel_id] in final.get("tags", [])
    )
    user_p_tagged = float(root is not None and _has_p_tag(root, agent_pubkey))
    content_has_no_wake_prefix_score = float(
        content_has_no_wake_prefix(root_content) and content_has_no_wake_prefix(final_content)
    )
    reward = float(
        all(
            metric == 1.0
            for metric in (
                evidence_complete,
                expected_author,
                same_channel,
                user_p_tagged,
                content_has_no_wake_prefix_score,
            )
        )
    )
    metrics = {
        "reward": reward,
        "user_p_tagged": user_p_tagged,
        "same_channel": same_channel,
        "expected_author": expected_author,
        "content_has_no_wake_prefix": content_has_no_wake_prefix_score,
        "evidence_complete": evidence_complete,
    }
    details = {
        "task_event_id": task_event_id,
        "root_content": root_content,
        "selected_message_id": final.get("id") if final is not None else None,
        "selected_message_content": final_content if final is not None else None,
        "agent_pubkey": agent_pubkey,
    }
    return metrics, details


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--reward", type=Path, required=True)
    parser.add_argument("--details", type=Path, required=True)
    args = parser.parse_args()

    try:
        evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
        metrics, details = score_evidence(evidence)
    except (OSError, json.JSONDecodeError) as error:
        metrics, details = _zero_metrics(), {"error": str(error)}

    args.reward.write_text(json.dumps(metrics, sort_keys=True) + "\n", encoding="utf-8")
    args.details.write_text(
        json.dumps(details, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
