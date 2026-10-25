//! Buzz-agent wires real mirofish-mcp-server (stdio) when backend is up.
//! Run: MIROFISH_BUZZ_SMOKE=1 cargo test -p buzz-agent mirofish_mcp -- --nocapture

mod common;

use common::{openai_text, openai_tool_call, spawn_capturing_llm, Harness};
use serde_json::json;
use std::path::PathBuf;
use std::time::Duration;

fn experiments_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../../")
}

fn mirofish_stdio_script() -> Option<PathBuf> {
    let script = experiments_root().join("mirofish-mcp-server/scripts/run-stdio.sh");
    let dist = experiments_root().join("mirofish-mcp-server/dist/index.js");
    if script.is_file() && dist.is_file() {
        Some(script)
    } else {
        None
    }
}

async fn backend_healthy() -> bool {
    reqwest::Client::new()
        .get("http://127.0.0.1:5001/health")
        .timeout(Duration::from_secs(3))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn mirofish_mcp_session_new_succeeds() {
    if std::env::var("MIROFISH_BUZZ_SMOKE").ok().as_deref() != Some("1") {
        eprintln!("skip mirofish_mcp_session (set MIROFISH_BUZZ_SMOKE=1)");
        return;
    }
    let script = mirofish_stdio_script()
        .expect("build mirofish-mcp-server (npm run build) and run-stdio.sh");
    assert!(
        backend_healthy().await,
        "MiroFish backend not on :5001 — restart with ZEP_SHIM_BASE_URL"
    );

    let llm = common::spawn_capturing_llm(vec![common::openai_text("ok")]).await;
    let mut h = Harness::spawn_with_env(
        &llm.url,
        &[
            ("BUZZ_AGENT_MCP_INIT_TIMEOUT_SECS", "30"),
            ("MIROFISH_BASE_URL", "http://127.0.0.1:5001"),
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
            "mcpServers": [{
                "name": "mirofish-mcp-server",
                "command": script.to_string_lossy(),
                "args": [],
                "env": [
                    {"name": "MIROFISH_BASE_URL", "value": "http://127.0.0.1:5001"},
                ],
            }],
        }),
    )
    .await;

    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;
    assert!(
        r.get("error").is_none(),
        "session/new failed: {r} stderr={}",
        h.stderr_text()
    );
    assert!(
        r["result"]["sessionId"].as_str().is_some(),
        "missing sessionId: {r}"
    );
}

fn mirofish_tool(name: &str) -> String {
    format!("mirofish-mcp-server__{name}")
}

async fn init_mirofish_session(h: &mut Harness, script: &PathBuf) -> String {
    h.send(
        "initialize",
        json!({"protocolVersion":1,"clientCapabilities":{}}),
    )
    .await;
    let _ = h.recv().await;

    let req = h
        .send(
            "session/new",
            json!({
                "cwd": "/tmp",
                "mcpServers": [{
                    "name": "mirofish-mcp-server",
                    "command": script.to_string_lossy(),
                    "args": [],
                    "env": [
                        {"name": "MIROFISH_BASE_URL", "value": "http://127.0.0.1:5001"},
                    ],
                }],
            }),
        )
        .await;

    let r = h
        .recv_until(|v| v.get("result").is_some() || v.get("error").is_some())
        .await;
    assert!(r.get("error").is_none(), "session/new failed: {r}");
    assert_eq!(r["id"], req);
    r["result"]["sessionId"]
        .as_str()
        .expect("sessionId")
        .to_owned()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn mirofish_mcp_live_optional_analysis_via_buzz_agent() {
    if std::env::var("MIROFISH_BUZZ_SMOKE").ok().as_deref() != Some("1") {
        eprintln!("skip mirofish_mcp_live_optional_analysis (set MIROFISH_BUZZ_SMOKE=1)");
        return;
    }
    let script = mirofish_stdio_script().expect("build mirofish-mcp-server (npm run build)");
    assert!(backend_healthy().await, "MiroFish backend not on :5001");

    let sim_id =
        std::env::var("MIROFISH_FIXTURE_SIMULATION").unwrap_or_else(|_| "sim_a461f61a9abf".into());

    let list_tool = mirofish_tool("mirofish_list_optional_analysis_engines");
    let run_tool = mirofish_tool("mirofish_run_optional_analysis");

    let mut llm_responses = vec![openai_tool_call("tc_list", &list_tool, json!({}))];
    for (i, engine) in [
        "oasis",
        "agenttorch",
        "concordia",
        "sotopia",
        "baseten_chainlet",
    ]
    .into_iter()
    .enumerate()
    {
        llm_responses.push(openai_tool_call(
            &format!("tc_run_{i}"),
            &run_tool,
            json!({ "simulation_id": sim_id, "engine": engine }),
        ));
    }
    llm_responses.push(openai_text("optional analysis live test complete"));

    let llm = spawn_capturing_llm(llm_responses).await;
    let mut h = Harness::spawn_with_env(
        &llm.url,
        &[
            ("BUZZ_AGENT_MCP_INIT_TIMEOUT_SECS", "60"),
            ("BUZZ_AGENT_TOOL_TIMEOUT_SECS", "180"),
            ("BUZZ_AGENT_MAX_ROUNDS", "24"),
            ("MIROFISH_BASE_URL", "http://127.0.0.1:5001"),
        ],
    )
    .await;

    let sid = init_mirofish_session(&mut h, &script).await;

    let prompt_id = h
        .send(
            "session/prompt",
            json!({
                "sessionId": sid,
                "prompt": [{"type":"text","text":"Live-test all optional analysis engines via MCP"}],
            }),
        )
        .await;

    let final_resp = h
        .recv_until_approving(|v| v.get("id") == Some(&json!(prompt_id)))
        .await;
    assert!(
        final_resp.get("result").is_some(),
        "prompt failed: {final_resp} stderr={}",
        h.stderr_text()
    );

    let captured = llm.captured.lock().await;
    assert!(
        captured.len() >= 7,
        "expected multi-round tool loop, got {} LLM calls",
        captured.len()
    );

    let all_tool_text: String = captured
        .iter()
        .flat_map(|req| {
            req["messages"]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|m| m["role"] == "tool")
                .filter_map(|m| m["content"].as_str())
        })
        .collect::<Vec<_>>()
        .join("\n");

    for needle in [
        "oasis",
        "agenttorch",
        "concordia",
        "sotopia",
        "baseten_chainlet",
    ] {
        assert!(
            all_tool_text.contains(needle),
            "missing engine {needle} in tool results: {}",
            all_tool_text.chars().take(400).collect::<String>()
        );
    }

    h.shutdown().await;
}
