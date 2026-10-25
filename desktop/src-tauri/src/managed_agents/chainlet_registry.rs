//! Agent ↔ chainlet specialty registry (Welcome Team + platform development + portfolio).
//!
//! Source YAML (compile-time embedded):
//! - `gpu-inference-stack/config/agent-chainlet-registry.yaml`
//! - `gpu-inference-stack/config/baseten-chain-portfolio.yaml`
//!
//! At spawn, `persona_id` maps to `BUZZ_AGENT_CHAIN_SPECIALTY` when defined.

use std::collections::HashMap;
use std::sync::OnceLock;

pub(crate) const BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR: &str = "BUZZ_AGENT_CHAIN_SPECIALTY";
pub(crate) const BUZZ_AGENT_CHAIN_MCP_DISABLE_ENV: &str = "BUZZ_AGENT_CHAIN_MCP";
pub(crate) const BUZZ_ACP_CHAIN_MCP_COMMAND_ENV: &str = "BUZZ_ACP_CHAIN_MCP_COMMAND";
pub(crate) const BASETEN_CHAIN_MCP_COMMAND_ENV: &str = "BASETEN_CHAIN_MCP_COMMAND";

const AGENT_CHAINLET_REGISTRY_YAML: &str =
    include_str!("../../../../../gpu-inference-stack/config/agent-chainlet-registry.yaml");
const BASETEN_CHAIN_PORTFOLIO_YAML: &str =
    include_str!("../../../../../gpu-inference-stack/config/baseten-chain-portfolio.yaml");

/// A chainlet specialty with optional persona binding and portfolio metadata.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChainletEntry {
    pub specialty: String,
    pub display_name: Option<String>,
    pub persona_id: Option<String>,
    pub title: Option<String>,
    pub model_tier: Option<String>,
    pub source: ChainletSource,
}

/// Whether the entry comes from the agent registry or portfolio catalog only.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChainletSource {
    AgentRegistry,
    Portfolio,
    Merged,
}

struct RegistryState {
    persona_to_specialty: HashMap<String, String>,
    entries: HashMap<String, ChainletEntry>,
}

static REGISTRY: OnceLock<RegistryState> = OnceLock::new();

fn specialty_from_agent_entry(agent: &serde_yaml::Mapping) -> Option<String> {
    if let Some(env) = agent
        .get(serde_yaml::Value::String("env".into()))
        .and_then(|v| v.as_mapping())
    {
        let key = serde_yaml::Value::String(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR.into());
        if let Some(value) = env.get(&key).and_then(|v| v.as_str()) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    agent
        .get(serde_yaml::Value::String("chain_specialty".into()))
        .and_then(|v| v.as_str())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn parse_agent_registry(state: &mut RegistryState) {
    let root = match serde_yaml::from_str::<serde_yaml::Value>(AGENT_CHAINLET_REGISTRY_YAML) {
        Ok(value) => value,
        Err(error) => {
            tracing::warn!("chainlet_registry: failed to parse agent registry: {error}");
            return;
        }
    };
    let agents = root
        .as_mapping()
        .and_then(|mapping| mapping.get(serde_yaml::Value::String("agents".into())))
        .and_then(|value| value.as_mapping());
    let Some(agents) = agents else {
        return;
    };
    for agent in agents.values() {
        let Some(agent_map) = agent.as_mapping() else {
            continue;
        };
        let persona_id = agent_map
            .get(serde_yaml::Value::String("persona_id".into()))
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|id| !id.is_empty());
        let display_name = agent_map
            .get(serde_yaml::Value::String("display_name".into()))
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(str::to_string);
        let specialty = specialty_from_agent_entry(agent_map);
        if let (Some(persona_id), Some(specialty)) = (persona_id, specialty) {
            state
                .persona_to_specialty
                .insert(persona_id.to_string(), specialty.clone());
            let entry = state
                .entries
                .entry(specialty.clone())
                .or_insert_with(|| ChainletEntry {
                    specialty: specialty.clone(),
                    display_name: display_name.clone(),
                    persona_id: Some(persona_id.to_string()),
                    title: None,
                    model_tier: None,
                    source: ChainletSource::AgentRegistry,
                });
            entry.display_name = display_name.or(entry.display_name.clone());
            entry.persona_id = Some(persona_id.to_string());
            if entry.source == ChainletSource::Portfolio {
                entry.source = ChainletSource::Merged;
            }
        }
    }
}

fn parse_portfolio(state: &mut RegistryState) {
    let root = match serde_yaml::from_str::<serde_yaml::Value>(BASETEN_CHAIN_PORTFOLIO_YAML) {
        Ok(value) => value,
        Err(error) => {
            tracing::warn!("chainlet_registry: failed to parse portfolio: {error}");
            return;
        }
    };
    let specialties = root
        .as_mapping()
        .and_then(|mapping| mapping.get(serde_yaml::Value::String("specialties".into())))
        .and_then(|value| value.as_mapping());
    let Some(specialties) = specialties else {
        return;
    };
    for (key, value) in specialties {
        let specialty = key.as_str().unwrap_or("").trim();
        if specialty.is_empty() {
            continue;
        }
        let meta = value.as_mapping();
        let title = meta
            .and_then(|m| m.get(serde_yaml::Value::String("title".into())))
            .and_then(|v| v.as_str())
            .map(str::to_string);
        let model_tier = meta
            .and_then(|m| m.get(serde_yaml::Value::String("model_tier".into())))
            .and_then(|v| v.as_str())
            .map(str::to_string);
        match state.entries.get_mut(specialty) {
            Some(entry) => {
                entry.title = title.or(entry.title.clone());
                entry.model_tier = model_tier.or(entry.model_tier.clone());
                if entry.source == ChainletSource::AgentRegistry {
                    entry.source = ChainletSource::Merged;
                }
            }
            None => {
                state.entries.insert(
                    specialty.to_string(),
                    ChainletEntry {
                        specialty: specialty.to_string(),
                        display_name: None,
                        persona_id: None,
                        title,
                        model_tier,
                        source: ChainletSource::Portfolio,
                    },
                );
            }
        }
    }
}

fn load_registry() -> RegistryState {
    let mut state = RegistryState {
        persona_to_specialty: HashMap::new(),
        entries: HashMap::new(),
    };
    parse_agent_registry(&mut state);
    parse_portfolio(&mut state);
    state
}

fn registry() -> &'static RegistryState {
    REGISTRY.get_or_init(load_registry)
}

/// All known chainlet specialties (agent-bound + portfolio-only), sorted by specialty name.
pub fn list_chainlets() -> Vec<ChainletEntry> {
    let mut entries: Vec<ChainletEntry> = registry().entries.values().cloned().collect();
    entries.sort_by(|a, b| a.specialty.cmp(&b.specialty));
    entries
}

/// Resolve specialty string for a persona id (e.g. `builtin:fizz`).
pub(crate) fn chain_specialty_for_persona(persona_id: &str) -> Option<&str> {
    registry()
        .persona_to_specialty
        .get(persona_id.trim())
        .map(|value| value.as_str())
}

/// Lookup a chainlet entry by specialty name.
pub fn chainlet_for_specialty(specialty: &str) -> Option<ChainletEntry> {
    registry().entries.get(specialty.trim()).cloned()
}

/// Lookup chainlet entry for a persona id.
pub fn chainlet_for_persona(persona_id: &str) -> Option<ChainletEntry> {
    chain_specialty_for_persona(persona_id).and_then(|specialty| chainlet_for_specialty(specialty))
}

/// Inject persona chain specialty after user env is applied so registry wins.
/// Agents without a `persona_id` keep any user-supplied specialty from `descriptor.env`.
pub(crate) fn apply_chain_specialty_env(
    command: &mut std::process::Command,
    persona_id: Option<&str>,
) {
    match persona_id {
        Some(id) => match chain_specialty_for_persona(id) {
            Some(specialty) => {
                command.env(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR, specialty);
            }
            None => {
                command.env_remove(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR);
            }
        },
        None => {}
    }
}

/// Attach baseten-chain-mcp as a second ACP MCP server for chainlet personas.
pub(crate) fn apply_chain_mcp_env(
    command: &mut std::process::Command,
    persona_id: Option<&str>,
    chain_mcp_enabled: bool,
    resolve_command: impl Fn(&str) -> Option<std::path::PathBuf>,
) {
    if !chain_mcp_enabled || std::env::var(BUZZ_AGENT_CHAIN_MCP_DISABLE_ENV).as_deref() == Ok("0") {
        command.env_remove(BUZZ_ACP_CHAIN_MCP_COMMAND_ENV);
        return;
    }
    let has_specialty = persona_id.and_then(chain_specialty_for_persona).is_some();
    if !has_specialty {
        command.env_remove(BUZZ_ACP_CHAIN_MCP_COMMAND_ENV);
        return;
    }
    let cmd = std::env::var(BASETEN_CHAIN_MCP_COMMAND_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| resolve_command("baseten-chain-mcp").map(|p| p.to_string_lossy().into_owned()));
    if let Some(cmd) = cmd {
        command.env(BUZZ_ACP_CHAIN_MCP_COMMAND_ENV, cmd);
    } else {
        command.env_remove(BUZZ_ACP_CHAIN_MCP_COMMAND_ENV);
    }
}

pub(crate) const BUZZ_AGENT_MIROFISH_MCP_DISABLE_ENV: &str = "BUZZ_AGENT_MIROFISH_MCP";
pub(crate) const BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV: &str = "BUZZ_ACP_MIROFISH_MCP_COMMAND";
pub(crate) const MIROFISH_MCP_COMMAND_ENV: &str = "MIROFISH_MCP_COMMAND";
pub(crate) const MIROFISH_BASE_URL_ENV: &str = "MIROFISH_BASE_URL";

/// Attach mirofish-mcp-server when MIROFISH_MCP_COMMAND resolves (opt-out via BUZZ_AGENT_MIROFISH_MCP=0).
pub(crate) fn apply_mirofish_mcp_env(
    command: &mut std::process::Command,
    mirofish_mcp_enabled: bool,
    mirofish_base_url_override: Option<String>,
    resolve_command: impl Fn(&str) -> Option<std::path::PathBuf>,
) {
    if !mirofish_mcp_enabled
        || std::env::var(BUZZ_AGENT_MIROFISH_MCP_DISABLE_ENV).as_deref() == Ok("0")
    {
        command.env_remove(BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV);
        return;
    }
    let cmd = std::env::var(MIROFISH_MCP_COMMAND_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| {
            resolve_command("mirofish-mcp-server").map(|p| p.to_string_lossy().into_owned())
        });
    if let Some(cmd) = cmd {
        command.env(BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV, cmd);
    } else {
        command.env_remove(BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV);
    }
    if let Ok(url) = std::env::var(MIROFISH_BASE_URL_ENV) {
        let trimmed = url.trim();
        if !trimmed.is_empty() {
            command.env(MIROFISH_BASE_URL_ENV, trimmed);
        }
    } else if let Some(url) = mirofish_base_url_override {
        command.env(MIROFISH_BASE_URL_ENV, url);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        apply_chain_specialty_env, chain_specialty_for_persona, chainlet_for_persona,
        chainlet_for_specialty, list_chainlets, ChainletSource, BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR,
    };

    fn env_of(cmd: &std::process::Command, key: &str) -> Option<String> {
        cmd.get_envs()
            .find(|(name, _)| *name == std::ffi::OsStr::new(key))
            .and_then(|(_, value)| value)
            .map(|value| value.to_string_lossy().into_owned())
    }

    #[test]
    fn welcome_team_specialties_resolve() {
        assert_eq!(
            chain_specialty_for_persona("builtin:fizz"),
            Some("ontology-action-draft")
        );
        assert_eq!(
            chain_specialty_for_persona("builtin:honey"),
            Some("verify-gate-plan")
        );
        assert_eq!(
            chain_specialty_for_persona("builtin:bumble"),
            Some("ontology-research-brief")
        );
    }

    #[test]
    fn platform_dev_specialties_resolve() {
        assert_eq!(
            chain_specialty_for_persona("builtin:chain"),
            Some("platform-chain-submit")
        );
        assert_eq!(
            chain_specialty_for_persona("builtin:gate"),
            Some("platform-formal-verify")
        );
        assert_eq!(chain_specialty_for_persona("builtin:tempo"), None);
        assert_eq!(chain_specialty_for_persona("builtin:sandbox"), None);
        assert_eq!(chain_specialty_for_persona("builtin:e2e"), None);
    }

    #[test]
    fn portfolio_specialties_included() {
        let roadmap = chainlet_for_specialty("roadmap").expect("roadmap specialty");
        assert_eq!(roadmap.source, ChainletSource::Portfolio);
        assert!(roadmap.title.is_some());
    }

    #[test]
    fn merged_entries_have_persona_and_title() {
        let fizz = chainlet_for_persona("builtin:fizz").expect("fizz chainlet");
        assert_eq!(fizz.specialty, "ontology-action-draft");
        assert_eq!(fizz.display_name.as_deref(), Some("Fizz"));
        assert_eq!(fizz.source, ChainletSource::Merged);
        assert!(fizz.title.is_some());
    }

    #[test]
    fn list_chainlets_non_empty() {
        assert!(list_chainlets().len() >= 10);
    }

    #[test]
    fn chain_specialty_env_injected_for_known_persona() {
        let mut cmd = std::process::Command::new("true");
        apply_chain_specialty_env(&mut cmd, Some("builtin:fizz"));
        assert_eq!(
            env_of(&cmd, BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR).as_deref(),
            Some("ontology-action-draft")
        );
    }

    #[test]
    fn chain_specialty_env_wins_over_user_env_collision() {
        let mut cmd = std::process::Command::new("true");
        cmd.env(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR, "stale-specialty");
        apply_chain_specialty_env(&mut cmd, Some("builtin:chain"));
        assert_eq!(
            env_of(&cmd, BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR).as_deref(),
            Some("platform-chain-submit")
        );
    }

    #[test]
    fn chain_specialty_env_removed_for_persona_without_specialty() {
        let mut cmd = std::process::Command::new("true");
        cmd.env(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR, "manual-dev");
        apply_chain_specialty_env(&mut cmd, Some("builtin:tempo"));
        assert_eq!(env_of(&cmd, BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR), None);
    }

    #[test]
    fn chain_specialty_env_preserved_without_persona_id() {
        let mut cmd = std::process::Command::new("true");
        cmd.env(BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR, "manual-dev");
        apply_chain_specialty_env(&mut cmd, None);
        assert_eq!(
            env_of(&cmd, BUZZ_AGENT_CHAIN_SPECIALTY_ENV_VAR).as_deref(),
            Some("manual-dev")
        );
    }

    #[test]
    fn mirofish_mcp_env_injected_from_operator_env() {
        use super::{
            apply_mirofish_mcp_env, BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV, MIROFISH_BASE_URL_ENV,
            MIROFISH_MCP_COMMAND_ENV,
        };
        let mut cmd = std::process::Command::new("true");
        std::env::set_var(MIROFISH_MCP_COMMAND_ENV, "/tmp/mirofish-mcp");
        std::env::set_var(MIROFISH_BASE_URL_ENV, "http://127.0.0.1:5001");
        apply_mirofish_mcp_env(&mut cmd, true, None, |_| None);
        std::env::remove_var(MIROFISH_MCP_COMMAND_ENV);
        std::env::remove_var(MIROFISH_BASE_URL_ENV);
        assert_eq!(
            env_of(&cmd, BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV).as_deref(),
            Some("/tmp/mirofish-mcp")
        );
        assert_eq!(
            env_of(&cmd, MIROFISH_BASE_URL_ENV).as_deref(),
            Some("http://127.0.0.1:5001")
        );
    }
}
