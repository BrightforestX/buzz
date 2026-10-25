//! Session-start ontology preflight via px-validate `validate_proposal`.
//!
//! When `BUZZ_AGENT_ONTOLOGY_GATE=1`, `session/new` calls `validate_proposal` on
//! the first MCP server that exposes it. Rejection or MCP failure fails closed —
//! no session is created.

use std::sync::Arc;

use serde_json::{json, Value};
use tokio::sync::watch;

use crate::config::Config;
use crate::mcp::{McpRegistry, ResultBudget};

const PREFLIGHT_RESULT_BUDGET: usize = 16 * 1024;
use crate::types::AgentError;

const PREFLIGHT_TOOL: &str = "validate_proposal";

/// Run ontology preflight when the gate is enabled. No-op when disabled.
pub async fn run_preflight(mcp: &Arc<McpRegistry>, cfg: &Config) -> Result<(), AgentError> {
    if !cfg.ontology_gate {
        return Ok(());
    }

    let qname = mcp.find_bare_tool(PREFLIGHT_TOOL).ok_or_else(|| {
        AgentError::InvalidParams(format!(
            "ontology gate: {PREFLIGHT_TOOL} not found on any MCP server"
        ))
    })?;

    let arguments = json!({
        "data": {},
        "class_name": cfg.ontology_preflight_class,
        "check_registry": false,
    });

    let (_cancel_hold, mut cancel) = watch::channel(false);
    cancel.borrow_and_update();
    let budget = ResultBudget {
        total: PREFLIGHT_RESULT_BUDGET,
        text: PREFLIGHT_RESULT_BUDGET,
    };

    let result = tokio::time::timeout(
        cfg.ontology_gate_timeout,
        mcp.call(
            &qname,
            "ontology_preflight",
            &arguments,
            budget,
            &mut cancel,
        ),
    )
    .await
    .map_err(|_| {
        AgentError::InvalidParams(format!(
            "ontology gate: {PREFLIGHT_TOOL} timed out after {}ms",
            cfg.ontology_gate_timeout.as_millis()
        ))
    })?
    .map_err(|e| AgentError::InvalidParams(format!("ontology gate: {e}")))?;

    if result.is_error {
        return Err(AgentError::InvalidParams(format!(
            "ontology gate: {PREFLIGHT_TOOL} returned isError"
        )));
    }

    parse_validate_proposal_ok(&result.text()).map_err(AgentError::InvalidParams)
}

/// Interpret px-validate / fake-mcp `validate_proposal` JSON text.
pub fn parse_validate_proposal_ok(text: &str) -> Result<(), String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err("ontology gate: empty validate_proposal response".into());
    }

    let value: Value = serde_json::from_str(trimmed)
        .map_err(|e| format!("ontology gate: invalid JSON from validate_proposal: {e}"))?;

    if value.get("ok").and_then(Value::as_bool) == Some(true) {
        return Ok(());
    }

    if let Some(errors) = value.get("errors").and_then(Value::as_array) {
        if !errors.is_empty() {
            return Err(format!(
                "ontology gate: validate_proposal rejected: {}",
                errors
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("; ")
            ));
        }
    }

    Err(format!(
        "ontology gate: validate_proposal failed: {}",
        trimmed.chars().take(512).collect::<String>()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_ok_true() {
        assert!(parse_validate_proposal_ok(r#"{"ok":true}"#).is_ok());
    }

    #[test]
    fn rejects_ok_false_with_errors() {
        let err = parse_validate_proposal_ok(r#"{"ok":false,"errors":["bad class"]}"#).unwrap_err();
        assert!(err.contains("bad class"));
    }

    #[test]
    fn rejects_missing_ok() {
        assert!(parse_validate_proposal_ok(r#"{"status":"unknown"}"#).is_err());
    }
}
