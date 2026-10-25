//! Integration tests for BUZZ_AGENT_ONTOLOGY_GATE session/new preflight.

use serde_json::json;

mod common;
use common::{spawn_capturing_llm, Harness};

fn fake_px_validate_mcp(fake_mcp: &str, extra_env: &[(&str, &str)]) -> serde_json::Value {
    let mut env = vec![
        json!({ "name": "FAKE_MCP_VALIDATE_PROPOSAL", "value": "1" }),
        json!({ "name": "FAKE_MCP_TOOL_COUNT", "value": "0" }),
    ];
    for (k, v) in extra_env {
        env.push(json!({ "name": k, "value": v }));
    }
    json!([{
        "name": "px-validate",
        "command": fake_mcp,
        "args": [],
        "env": env,
    }])
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn ontology_gate_allows_session_when_validate_passes() {
    let llm = spawn_capturing_llm(vec![]).await;
    let fake_mcp = env!("CARGO_BIN_EXE_fake-mcp");
    let mut h = Harness::spawn_with_env(
        &llm.url,
        &[
            ("BUZZ_AGENT_ONTOLOGY_GATE", "1"),
            ("BUZZ_AGENT_ONTOLOGY_GATE_TIMEOUT_MS", "2000"),
        ],
    )
    .await;

    h.send(
        "initialize",
        json!({"protocolVersion":1,"clientCapabilities":{}}),
    )
    .await;
    let _ = h.recv().await;

    h.send(
        "session/new",
        json!({
            "cwd": "/tmp",
            "mcpServers": fake_px_validate_mcp(fake_mcp, &[]),
        }),
    )
    .await;
    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;

    assert!(
        r.get("result").and_then(|x| x.get("sessionId")).is_some(),
        "expected sessionId, got {r}, stderr={}",
        h.stderr_text()
    );
    h.shutdown().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn ontology_gate_blocks_session_when_validate_fails() {
    let llm = spawn_capturing_llm(vec![]).await;
    let fake_mcp = env!("CARGO_BIN_EXE_fake-mcp");
    let mut h = Harness::spawn_with_env(
        &llm.url,
        &[
            ("BUZZ_AGENT_ONTOLOGY_GATE", "1"),
            ("BUZZ_AGENT_ONTOLOGY_GATE_TIMEOUT_MS", "2000"),
        ],
    )
    .await;

    h.send(
        "initialize",
        json!({"protocolVersion":1,"clientCapabilities":{}}),
    )
    .await;
    let _ = h.recv().await;

    h.send(
        "session/new",
        json!({
            "cwd": "/tmp",
            "mcpServers": fake_px_validate_mcp(fake_mcp, &[("FAKE_MCP_VALIDATE_FAIL", "1")]),
        }),
    )
    .await;
    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;

    assert!(r.get("error").is_some(), "expected error, got {r}");
    let msg = r["error"]["message"].as_str().unwrap_or("");
    assert!(
        msg.contains("ontology gate"),
        "expected ontology gate error, got: {msg}"
    );
    h.shutdown().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn ontology_gate_fails_closed_when_tool_missing() {
    let llm = spawn_capturing_llm(vec![]).await;
    let mut h = Harness::spawn_with_env(
        &llm.url,
        &[
            ("BUZZ_AGENT_ONTOLOGY_GATE", "1"),
            ("BUZZ_AGENT_ONTOLOGY_GATE_TIMEOUT_MS", "2000"),
        ],
    )
    .await;

    h.send(
        "initialize",
        json!({"protocolVersion":1,"clientCapabilities":{}}),
    )
    .await;
    let _ = h.recv().await;

    h.send(
        "session/new",
        json!({"cwd": "/tmp", "mcpServers": json!([])}),
    )
    .await;
    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;

    assert!(r.get("error").is_some(), "expected error, got {r}");
    let msg = r["error"]["message"].as_str().unwrap_or("");
    assert!(
        msg.contains("validate_proposal"),
        "expected missing-tool error, got: {msg}"
    );
    h.shutdown().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn ontology_gate_disabled_skips_preflight() {
    let llm = spawn_capturing_llm(vec![]).await;
    let mut h = Harness::spawn_with_env(&llm.url, &[]).await;

    h.send(
        "initialize",
        json!({"protocolVersion":1,"clientCapabilities":{}}),
    )
    .await;
    let _ = h.recv().await;

    h.send(
        "session/new",
        json!({"cwd": "/tmp", "mcpServers": json!([])}),
    )
    .await;
    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;

    assert!(
        r.get("result").and_then(|x| x.get("sessionId")).is_some(),
        "expected session without gate, got {r}"
    );
    h.shutdown().await;
}
