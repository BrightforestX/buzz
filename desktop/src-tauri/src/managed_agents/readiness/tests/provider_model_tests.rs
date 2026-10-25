//! Provider-specific model fallback readiness tests (kept out of readiness.rs for file-size ratchet).

use super::*;

#[test]
fn buzz_agent_anthropic_with_anthropic_model_but_no_buzz_agent_model_is_ready() {
    let env = make_env(
        "buzz-agent",
        env_with(&[
            ("BUZZ_AGENT_PROVIDER", "anthropic"),
            ("ANTHROPIC_MODEL", "claude-opus-4-5"),
            ("ANTHROPIC_API_KEY", "sk-test"),
        ]),
    );
    assert!(
        agent_readiness(&env).is_ready(),
        "ANTHROPIC_MODEL must satisfy the model requirement for anthropic"
    );
}

#[test]
fn buzz_agent_openai_with_openai_compat_model_but_no_buzz_agent_model_is_ready() {
    let env = make_env(
        "buzz-agent",
        env_with(&[
            ("BUZZ_AGENT_PROVIDER", "openai"),
            ("OPENAI_COMPAT_MODEL", "gpt-4o"),
            ("OPENAI_COMPAT_API_KEY", "sk-test"),
        ]),
    );
    assert!(
        agent_readiness(&env).is_ready(),
        "OPENAI_COMPAT_MODEL must satisfy the model requirement for openai"
    );
}

#[test]
fn buzz_agent_empty_provider_model_fallback_key_is_not_ready() {
    let env = make_env(
        "buzz-agent",
        env_with(&[
            ("BUZZ_AGENT_PROVIDER", "databricks_v2"),
            ("DATABRICKS_MODEL", ""),
            ("DATABRICKS_HOST", "https://dbc.example.com"),
        ]),
    );
    let result = agent_readiness(&env);
    assert!(
        !result.is_ready(),
        "empty DATABRICKS_MODEL with no BUZZ_AGENT_MODEL must be NotReady"
    );
    assert!(result
        .requirements()
        .contains(&Requirement::NormalizedField {
            field: "model".to_string()
        }));
}
