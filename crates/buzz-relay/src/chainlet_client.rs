//! Relay-side headless chainlet execution via `baseten_chain_mcp.relay_invoke`.

use std::process::Stdio;
use std::time::Duration;

use buzz_workflow::action_sink::ActionSinkError;
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tracing::warn;

const DEFAULT_INVOKE: &str = "python3 -m baseten_chain_mcp.relay_invoke";

/// Invoke a chainlet specialty and poll until terminal or timeout.
pub async fn invoke_chainlet(
    specialty: &str,
    tenant: &str,
    subject: &str,
    spec_override: Option<&Value>,
    timeout_secs: u64,
) -> Result<Value, ActionSinkError> {
    let specialty = specialty.trim();
    if specialty.is_empty() {
        return Err(ActionSinkError::InvalidInput(
            "invoke_chainlet: specialty is required".into(),
        ));
    }

    let invoke_cmd = std::env::var("BASETEN_CHAIN_INVOKE_COMMAND")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_INVOKE.to_string());

    let mut parts: Vec<String> = invoke_cmd.split_whitespace().map(str::to_string).collect();
    if parts.is_empty() {
        return Err(ActionSinkError::InvalidInput(
            "BASETEN_CHAIN_INVOKE_COMMAND is empty".into(),
        ));
    }
    let program = parts.remove(0);
    parts.push("--stdin-json".to_string());

    let payload = json!({
        "specialty": specialty,
        "tenant": tenant,
        "subject": subject,
        "timeout_secs": timeout_secs,
        "spec": spec_override,
    });

    let mut child = Command::new(&program);
    child
        .args(&parts)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = child
        .spawn()
        .map_err(|e| ActionSinkError::Database(format!("failed to spawn chainlet invoke: {e}")))?;

    if let Some(mut stdin) = child.stdin.take() {
        let body = serde_json::to_vec(&payload).map_err(|e| {
            ActionSinkError::InvalidInput(format!("invoke payload encode failed: {e}"))
        })?;
        stdin
            .write_all(&body)
            .await
            .map_err(|e| ActionSinkError::Database(format!("invoke stdin write failed: {e}")))?;
    }

    let output = tokio::time::timeout(
        Duration::from_secs(timeout_secs.saturating_add(30)),
        child.wait_with_output(),
    )
    .await
    .map_err(|_| {
        ActionSinkError::Database(format!(
            "chainlet invoke timed out after {}s",
            timeout_secs.saturating_add(30)
        ))
    })?
    .map_err(|e| ActionSinkError::Database(format!("chainlet invoke process failed: {e}")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        warn!(stderr = %stderr, "chainlet invoke exited with error");
        return Err(ActionSinkError::Database(format!(
            "chainlet invoke failed: {}",
            stderr.trim()
        )));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let value: Value = serde_json::from_str(stdout.trim()).map_err(|e| {
        ActionSinkError::Database(format!("chainlet invoke returned invalid JSON: {e}"))
    })?;
    Ok(value)
}
