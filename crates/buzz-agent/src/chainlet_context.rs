//! Session-start chainlet context from spawn env (`BUZZ_AGENT_CHAIN_SPECIALTY`, platform job).

use std::env;

const CHAIN_SPECIALTY_ENV: &str = "BUZZ_AGENT_CHAIN_SPECIALTY";
const PLATFORM_JOB_ID_ENV: &str = "BUZZ_PLATFORM_JOB_ID";
const PLATFORM_TENANT_ENV: &str = "BUZZ_PLATFORM_TENANT";
const SCENARIO_ID_ENV: &str = "BUZZ_SCENARIO_ID";
const TOOL_BACKEND_ENV: &str = "TOOL_BACKEND";

/// Build the chainlet context block from resolved env values (testable without env mutation).
pub(crate) fn format_chainlet_block(
    specialty: Option<&str>,
    job_id: Option<&str>,
    tenant: Option<&str>,
    scenario_id: Option<&str>,
    tool_backend: Option<&str>,
) -> Option<String> {
    if specialty.is_none() && job_id.is_none() && scenario_id.is_none() {
        return None;
    }

    let mut block = String::from("\n\n## Chainlet context\n");
    if let Some(s) = specialty {
        block.push_str(&format!(
            "- Assigned specialty: `{s}`. Use MCP tools `list_chainlets`, `validate_chain_spec`, then `submit_chain_job` (or `execute_chain` for sync dev).\n"
        ));
    } else {
        block.push_str(
            "- No `BUZZ_AGENT_CHAIN_SPECIALTY` set; discover specialties via `list_chainlets`.\n",
        );
    }
    if let Some(j) = job_id {
        block.push_str(&format!(
            "- Platform job `{j}` is active: chainlet output is authoritative for this turn; chat explains results, it does not invent writes.\n"
        ));
    }
    if let Some(t) = tenant {
        block.push_str(&format!("- Platform tenant: `{t}`.\n"));
    }
    if let Some(sid) = scenario_id {
        block.push_str(&format!(
            "- PM simulation scenario `{sid}` is active. Use `scenario_read_state`, `pm_get_issue_tool`, `pm_search_issues_tool`, `pm_add_comment_tool`, and `scenario_propose_action_tool` with `scenario_id` set. Default PM backend is replay (no live Jira/Asana).\n"
        ));
    }
    if let Some(backend) = tool_backend {
        block.push_str(&format!(
            "- PM tool backend: `{backend}` (`TOOL_BACKEND` env). Prefer replay/sandbox in batch runs.\n"
        ));
    }
    block.push_str(
        "- Constitution X.III: never call portfolio HTTP or `run_remote` from Buzz desktop; use baseten-chain-mcp only.\n",
    );
    Some(block)
}

/// Append a compact chainlet block when specialty or platform job env is set.
pub fn append_chainlet_context(prompt: String) -> String {
    let specialty = env::var(CHAIN_SPECIALTY_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let job_id = env::var(PLATFORM_JOB_ID_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let tenant = env::var(PLATFORM_TENANT_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let scenario_id = env::var(SCENARIO_ID_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let tool_backend = env::var(TOOL_BACKEND_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    match format_chainlet_block(
        specialty.as_deref(),
        job_id.as_deref(),
        tenant.as_deref(),
        scenario_id.as_deref(),
        tool_backend.as_deref(),
    ) {
        Some(block) => format!("{prompt}{block}"),
        None => prompt,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_chainlet_block_none_when_empty() {
        assert!(format_chainlet_block(None, None, None, None, None).is_none());
    }

    #[test]
    fn format_chainlet_block_includes_specialty_and_job() {
        let block = format_chainlet_block(
            Some("ontology-action-draft"),
            Some("job-1"),
            Some("brightforest"),
            None,
            None,
        )
        .expect("block");
        assert!(block.contains("ontology-action-draft"));
        assert!(block.contains("job-1"));
        assert!(block.contains("brightforest"));
        assert!(block.contains("list_chainlets"));
    }

    #[test]
    fn format_chainlet_block_includes_scenario_tools() {
        let block =
            format_chainlet_block(Some("fizz"), None, None, Some("scn_abc123"), Some("replay"))
                .expect("block");
        assert!(block.contains("scn_abc123"));
        assert!(block.contains("scenario_read_state"));
        assert!(block.contains("replay"));
    }
}
