pub const BASETEN_PROVIDER_ID: &str = "baseten";
/// Marker on the effective env so readiness can surface `BASETEN_API_KEY` instead
/// of the derived `OPENAI_COMPAT_API_KEY` after transport translation.
pub const BASETEN_NATIVE_ENV_MARKER: &str = "BUZZ_BASETEN_NATIVE";

const DEFAULT_BASETEN_INFERENCE_BASE: &str = "https://inference.baseten.co/v1";

fn env_value(env: &std::collections::BTreeMap<String, String>, key: &str) -> Option<String> {
    env.get(key)
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn normalize_openai_compat_base_url(base_url: &str) -> String {
    let trimmed = base_url.trim().trim_end_matches('/');
    if trimmed.ends_with("/v1") {
        trimmed.to_string()
    } else {
        format!("{trimmed}/v1")
    }
}

/// Resolve the OpenAI-compatible base URL for a Baseten-backed agent.
pub fn resolve_baseten_base_url(
    env: &std::collections::BTreeMap<String, String>,
) -> Option<String> {
    if let Some(url) = env_value(env, "OPENAI_COMPAT_BASE_URL") {
        return Some(normalize_openai_compat_base_url(&url));
    }
    if let Some(url) = env_value(env, "BASETEN_PROXY_BASE_URL") {
        return Some(normalize_openai_compat_base_url(&url));
    }
    if let Some(url) = env_value(env, "BASETEN_MODEL_APIS_BASE") {
        return Some(normalize_openai_compat_base_url(&url));
    }
    if let Some(model_id) = env_value(env, "BASETEN_MODEL_ID") {
        return Some(format!("https://model-{model_id}.api.baseten.co/v1"));
    }
    Some(DEFAULT_BASETEN_INFERENCE_BASE.to_string())
}

fn resolve_baseten_api_key(env: &std::collections::BTreeMap<String, String>) -> Option<String> {
    env_value(env, "BASETEN_API_KEY").or_else(|| env_value(env, "OPENAI_COMPAT_API_KEY"))
}

fn resolve_baseten_model(
    env: &std::collections::BTreeMap<String, String>,
    model: Option<&str>,
) -> Option<String> {
    model
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .or_else(|| env_value(env, "BUZZ_AGENT_MODEL"))
        .or_else(|| env_value(env, "BASETEN_MODEL"))
        .or_else(|| env_value(env, "OPENAI_COMPAT_MODEL"))
        .or_else(|| env_value(env, "BASETEN_MODEL_ID"))
}

/// Translate the native Baseten provider into buzz-agent's OpenAI-compatible
/// transport. Derived runtime details — not user-owned agent configuration.
pub fn apply_baseten_env(
    env: &mut std::collections::BTreeMap<String, String>,
    provider: Option<&str>,
    model: Option<&str>,
) {
    if provider.map(str::trim) != Some(BASETEN_PROVIDER_ID) {
        return;
    }

    env.insert(BASETEN_NATIVE_ENV_MARKER.to_string(), "1".to_string());

    let model = resolve_baseten_model(env, model);
    let base_url = resolve_baseten_base_url(env);
    let api_key = resolve_baseten_api_key(env);

    env.insert("BUZZ_AGENT_PROVIDER".to_string(), "openai".to_string());
    if let Some(model) = model {
        env.insert("BUZZ_AGENT_MODEL".to_string(), model.clone());
        env.insert("OPENAI_COMPAT_MODEL".to_string(), model);
    }
    if let Some(base_url) = base_url {
        env.insert("OPENAI_COMPAT_BASE_URL".to_string(), base_url);
    }
    if let Some(api_key) = api_key {
        env.insert("OPENAI_COMPAT_API_KEY".to_string(), api_key);
    }
    env.insert("OPENAI_COMPAT_API".to_string(), "chat".to_string());
    // Baseten agents (e.g. Kimi via proxy) often end turns without publishing;
    // enable the reply guard by default, same as mesh. Explicit `0` survives.
    insert_default_if_unset(env, "BUZZ_AGENT_REQUIRE_REPLY", "1");
}

fn insert_default_if_unset(
    env: &mut std::collections::BTreeMap<String, String>,
    key: &str,
    value: &str,
) {
    if env.get(key).is_none_or(|current| current.trim().is_empty()) {
        env.insert(key.to_string(), value.to_string());
    }
}

/// Build the final Baseten-specific process overrides from the already-resolved
/// harness environment. Written onto the command after the layered user env so
/// derived transport values remain authoritative.
pub fn baseten_process_env(
    effective_env: &std::collections::BTreeMap<String, String>,
    model: Option<&str>,
) -> std::collections::BTreeMap<String, String> {
    let mut env = std::collections::BTreeMap::new();
    apply_baseten_env(&mut env, Some(BASETEN_PROVIDER_ID), model);
    // Preserve explicit user overrides for generation controls and reply guard.
    for key in [
        "BUZZ_AGENT_MAX_OUTPUT_TOKENS",
        "BUZZ_AGENT_THINKING_EFFORT",
        "BUZZ_AGENT_REQUIRE_REPLY",
    ] {
        if let Some(value) = effective_env.get(key) {
            env.insert(key.to_string(), value.clone());
        }
    }
    env
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    #[test]
    fn proxy_base_url_wins_over_model_id() {
        let env = BTreeMap::from([
            (
                "BASETEN_PROXY_BASE_URL".to_string(),
                "https://proxy.example".to_string(),
            ),
            ("BASETEN_MODEL_ID".to_string(), "abc123".to_string()),
        ]);
        assert_eq!(
            resolve_baseten_base_url(&env),
            Some("https://proxy.example/v1".to_string())
        );
    }

    #[test]
    fn model_id_builds_direct_deployment_url() {
        let env = BTreeMap::from([("BASETEN_MODEL_ID".to_string(), "qelg6953".to_string())]);
        assert_eq!(
            resolve_baseten_base_url(&env),
            Some("https://model-qelg6953.api.baseten.co/v1".to_string())
        );
    }

    #[test]
    fn native_provider_maps_to_openai_compat_transport() {
        let mut env = BTreeMap::from([
            ("BASETEN_API_KEY".to_string(), "bt-test".to_string()),
            (
                "BASETEN_PROXY_BASE_URL".to_string(),
                "https://proxy.example/v1".to_string(),
            ),
        ]);
        apply_baseten_env(&mut env, Some(BASETEN_PROVIDER_ID), Some("my-model"));

        assert_eq!(
            env.get("BUZZ_AGENT_PROVIDER").map(String::as_str),
            Some("openai")
        );
        assert_eq!(
            env.get("OPENAI_COMPAT_API_KEY").map(String::as_str),
            Some("bt-test")
        );
        assert_eq!(
            env.get("OPENAI_COMPAT_BASE_URL").map(String::as_str),
            Some("https://proxy.example/v1")
        );
        assert_eq!(
            env.get("OPENAI_COMPAT_MODEL").map(String::as_str),
            Some("my-model")
        );
        assert_eq!(
            env.get(BASETEN_NATIVE_ENV_MARKER).map(String::as_str),
            Some("1")
        );
    }

    #[test]
    fn baseten_defaults_require_reply_guard() {
        let mut env = BTreeMap::from([("BASETEN_API_KEY".to_string(), "bt-test".to_string())]);
        apply_baseten_env(&mut env, Some(BASETEN_PROVIDER_ID), Some("my-model"));
        assert_eq!(
            env.get("BUZZ_AGENT_REQUIRE_REPLY").map(String::as_str),
            Some("1")
        );
    }

    #[test]
    fn baseten_respects_explicit_require_reply_off() {
        let mut env = BTreeMap::from([
            ("BASETEN_API_KEY".to_string(), "bt-test".to_string()),
            ("BUZZ_AGENT_REQUIRE_REPLY".to_string(), "0".to_string()),
        ]);
        apply_baseten_env(&mut env, Some(BASETEN_PROVIDER_ID), Some("my-model"));
        assert_eq!(
            env.get("BUZZ_AGENT_REQUIRE_REPLY").map(String::as_str),
            Some("0")
        );
    }

    #[test]
    fn non_baseten_provider_is_unchanged() {
        let mut env = BTreeMap::from([("ANTHROPIC_API_KEY".to_string(), "sk-ant".to_string())]);
        apply_baseten_env(&mut env, Some("anthropic"), Some("claude-haiku-4.5"));
        assert!(env.get("OPENAI_COMPAT_BASE_URL").is_none());
    }
}
