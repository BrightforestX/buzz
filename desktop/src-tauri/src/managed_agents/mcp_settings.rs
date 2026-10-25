use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

use crate::{app_state::AppState, managed_agents::storage::atomic_write_json_restricted};

const SETTINGS_FILE: &str = "agent-mcp-settings.json";
const CURRENT_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentMcpSettings {
    pub version: u32,
    pub chain_mcp_enabled: bool,
    pub mirofish_mcp_enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mirofish_base_url: Option<String>,
}

impl Default for AgentMcpSettings {
    fn default() -> Self {
        Self {
            version: CURRENT_VERSION,
            chain_mcp_enabled: true,
            mirofish_mcp_enabled: true,
            mirofish_base_url: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentMcpSettingsView {
    pub chain_mcp_enabled: bool,
    pub mirofish_mcp_enabled: bool,
    pub mirofish_base_url: Option<String>,
    pub chain_mcp_resolvable: bool,
    pub mirofish_mcp_resolvable: bool,
    pub resolved_chain_command: Option<String>,
    pub resolved_mirofish_command: Option<String>,
}

pub(crate) struct AgentMcpRuntimeState {
    pub(crate) chain_mcp_enabled: AtomicBool,
    pub(crate) mirofish_mcp_enabled: AtomicBool,
    pub(crate) mirofish_base_url_override: Mutex<String>,
}

impl Default for AgentMcpRuntimeState {
    fn default() -> Self {
        Self {
            chain_mcp_enabled: AtomicBool::new(true),
            mirofish_mcp_enabled: AtomicBool::new(true),
            mirofish_base_url_override: Mutex::new(String::new()),
        }
    }
}

impl AppState {
    pub(crate) fn agent_chain_mcp_enabled(&self) -> &AtomicBool {
        &self.agent_mcp.chain_mcp_enabled
    }

    pub(crate) fn agent_mirofish_mcp_enabled(&self) -> &AtomicBool {
        &self.agent_mcp.mirofish_mcp_enabled
    }

    pub(crate) fn mirofish_base_url_override(&self) -> &Mutex<String> {
        &self.agent_mcp.mirofish_base_url_override
    }
}

pub(crate) fn chain_mcp_enabled(state: &AppState) -> bool {
    state.agent_chain_mcp_enabled().load(Ordering::Acquire)
}

pub(crate) fn mirofish_mcp_enabled(state: &AppState) -> bool {
    state.agent_mirofish_mcp_enabled().load(Ordering::Acquire)
}

pub(crate) fn mirofish_base_url_override(state: &AppState) -> Option<String> {
    let guard = state
        .mirofish_base_url_override()
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    let trimmed = guard.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

pub(crate) fn settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|dir| dir.join(SETTINGS_FILE))
        .map_err(|error| format!("could not locate Buzz settings storage: {error}"))
}

pub(crate) fn load_from_path(path: &Path) -> Result<AgentMcpSettings, String> {
    if !path.exists() {
        return Ok(AgentMcpSettings::default());
    }
    let bytes = std::fs::read(path)
        .map_err(|error| format!("could not read agent MCP settings: {error}"))?;
    let mut settings: AgentMcpSettings = serde_json::from_slice(&bytes)
        .map_err(|error| format!("agent MCP settings are not valid JSON: {error}"))?;
    if settings.version == 0 {
        settings.version = CURRENT_VERSION;
    }
    if settings.version > CURRENT_VERSION {
        return Err(format!(
            "agent MCP settings version {} is newer than this Buzz build supports",
            settings.version
        ));
    }
    settings.version = CURRENT_VERSION;
    if let Some(url) = settings.mirofish_base_url.as_mut() {
        let trimmed = url.trim();
        if trimmed.is_empty() {
            settings.mirofish_base_url = None;
        } else {
            *url = trimmed.to_string();
        }
    }
    Ok(settings)
}

pub(crate) fn save_to_path(path: &Path, settings: &AgentMcpSettings) -> Result<(), String> {
    let payload = serde_json::to_vec_pretty(settings)
        .map_err(|error| format!("could not encode agent MCP settings: {error}"))?;
    atomic_write_json_restricted(path, &payload)
        .map_err(|error| format!("could not save agent MCP settings: {error}"))
}

pub(crate) fn sync_runtime_state(state: &AppState, settings: &AgentMcpSettings) {
    state
        .agent_chain_mcp_enabled()
        .store(settings.chain_mcp_enabled, Ordering::Release);
    state
        .agent_mirofish_mcp_enabled()
        .store(settings.mirofish_mcp_enabled, Ordering::Release);
    if let Ok(mut guard) = state.mirofish_base_url_override().lock() {
        *guard = settings.mirofish_base_url.clone().unwrap_or_default();
    }
}

pub fn load_for_app(app: &AppHandle) -> AgentMcpSettings {
    match settings_path(app).and_then(|path| load_from_path(&path)) {
        Ok(settings) => settings,
        Err(error) => {
            eprintln!("buzz-desktop: {error}; using default agent MCP settings for this session");
            AgentMcpSettings::default()
        }
    }
}

fn resolve_mcp_command(name: &str) -> Option<String> {
    super::discovery::resolve_command(name).map(|p| p.to_string_lossy().into_owned())
}

fn chain_command_available() -> (bool, Option<String>) {
    let from_env = std::env::var(super::chainlet_registry::BASETEN_CHAIN_MCP_COMMAND_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    if let Some(cmd) = from_env {
        return (true, Some(cmd));
    }
    resolve_mcp_command("baseten-chain-mcp")
        .map(|c| (true, Some(c)))
        .unwrap_or((false, None))
}

fn mirofish_command_available() -> (bool, Option<String>) {
    let from_env = std::env::var(super::chainlet_registry::MIROFISH_MCP_COMMAND_ENV)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    if let Some(cmd) = from_env {
        return (true, Some(cmd));
    }
    resolve_mcp_command("mirofish-mcp-server")
        .map(|c| (true, Some(c)))
        .unwrap_or((false, None))
}

pub fn build_settings_view(state: &AppState) -> AgentMcpSettingsView {
    let (chain_resolvable, resolved_chain) = chain_command_available();
    let (mirofish_resolvable, resolved_mirofish) = mirofish_command_available();
    AgentMcpSettingsView {
        chain_mcp_enabled: chain_mcp_enabled(state),
        mirofish_mcp_enabled: mirofish_mcp_enabled(state),
        mirofish_base_url: mirofish_base_url_override(state),
        chain_mcp_resolvable: chain_resolvable,
        mirofish_mcp_resolvable: mirofish_resolvable,
        resolved_chain_command: resolved_chain,
        resolved_mirofish_command: resolved_mirofish,
    }
}

pub fn persist_agent_mcp_settings(
    app: &AppHandle,
    state: &AppState,
    chain_mcp_enabled: bool,
    mirofish_mcp_enabled: bool,
    mirofish_base_url: Option<String>,
) -> Result<AgentMcpSettingsView, String> {
    let normalized_url = mirofish_base_url
        .map(|url| url.trim().to_string())
        .filter(|url| !url.is_empty());
    let settings = AgentMcpSettings {
        version: CURRENT_VERSION,
        chain_mcp_enabled,
        mirofish_mcp_enabled,
        mirofish_base_url: normalized_url,
    };
    let path = settings_path(app)?;
    save_to_path(&path, &settings)?;
    sync_runtime_state(state, &settings);
    Ok(build_settings_view(state))
}

pub(crate) fn apply_app_agent_mcp_env(
    app: &AppHandle,
    command: &mut std::process::Command,
    persona_id: Option<&str>,
    resolve_command: impl Fn(&str) -> Option<std::path::PathBuf>,
) {
    let state = app.state::<AppState>();
    let inner = state.inner();
    super::chainlet_registry::apply_chain_mcp_env(
        command,
        persona_id,
        chain_mcp_enabled(inner),
        &resolve_command,
    );
    super::chainlet_registry::apply_mirofish_mcp_env(
        command,
        mirofish_mcp_enabled(inner),
        mirofish_base_url_override(inner),
        &resolve_command,
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::managed_agents::chainlet_registry::{
        apply_chain_mcp_env, apply_mirofish_mcp_env, BUZZ_ACP_CHAIN_MCP_COMMAND_ENV,
        BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV, BUZZ_AGENT_MIROFISH_MCP_DISABLE_ENV,
        MIROFISH_BASE_URL_ENV, MIROFISH_MCP_COMMAND_ENV,
    };

    fn env_of(cmd: &std::process::Command, key: &str) -> Option<String> {
        cmd.get_envs()
            .find(|(name, _)| *name == std::ffi::OsStr::new(key))
            .and_then(|(_, value)| value)
            .map(|value| value.to_string_lossy().into_owned())
    }

    #[test]
    fn default_settings_enable_both_mcps() {
        let settings = AgentMcpSettings::default();
        assert!(settings.chain_mcp_enabled);
        assert!(settings.mirofish_mcp_enabled);
    }

    #[test]
    fn load_save_roundtrip_uses_camel_case_keys() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join(SETTINGS_FILE);
        let settings = AgentMcpSettings {
            version: CURRENT_VERSION,
            chain_mcp_enabled: false,
            mirofish_mcp_enabled: true,
            mirofish_base_url: Some("http://127.0.0.1:5001".to_string()),
        };
        save_to_path(&path, &settings).expect("save");
        let raw = std::fs::read_to_string(&path).expect("read");
        assert!(raw.contains("\"chainMcpEnabled\""));
        let loaded = load_from_path(&path).expect("load");
        assert_eq!(loaded, settings);
    }

    #[test]
    fn sync_runtime_state_reflects_disabled_chain_mcp() {
        let runtime = AgentMcpRuntimeState::default();
        let settings = AgentMcpSettings {
            version: CURRENT_VERSION,
            chain_mcp_enabled: false,
            mirofish_mcp_enabled: true,
            mirofish_base_url: None,
        };
        runtime
            .chain_mcp_enabled
            .store(settings.chain_mcp_enabled, Ordering::Release);
        runtime
            .mirofish_mcp_enabled
            .store(settings.mirofish_mcp_enabled, Ordering::Release);
        assert!(!runtime.chain_mcp_enabled.load(Ordering::Acquire));
        assert!(runtime.mirofish_mcp_enabled.load(Ordering::Acquire));
    }

    #[test]
    fn disabled_chain_toggle_strips_chain_mcp_env_even_with_specialty() {
        let mut cmd = std::process::Command::new("true");
        std::env::set_var(MIROFISH_MCP_COMMAND_ENV, "/tmp/mirofish-mcp");
        apply_chain_mcp_env(&mut cmd, Some("builtin:chain"), false, |_| None);
        assert_eq!(env_of(&cmd, BUZZ_ACP_CHAIN_MCP_COMMAND_ENV), None);
        std::env::remove_var(MIROFISH_MCP_COMMAND_ENV);
    }

    #[test]
    fn disabled_mirofish_toggle_strips_mcp_env() {
        let mut cmd = std::process::Command::new("true");
        std::env::set_var(MIROFISH_MCP_COMMAND_ENV, "/tmp/mirofish-mcp");
        apply_mirofish_mcp_env(&mut cmd, false, None, |_| None);
        assert_eq!(env_of(&cmd, BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV), None);
        std::env::remove_var(MIROFISH_MCP_COMMAND_ENV);
    }

    #[test]
    fn mirofish_env_disable_flag_still_wins() {
        let mut cmd = std::process::Command::new("true");
        std::env::set_var(MIROFISH_MCP_COMMAND_ENV, "/tmp/mirofish-mcp");
        std::env::set_var(BUZZ_AGENT_MIROFISH_MCP_DISABLE_ENV, "0");
        apply_mirofish_mcp_env(&mut cmd, true, None, |_| None);
        std::env::remove_var(MIROFISH_MCP_COMMAND_ENV);
        std::env::remove_var(BUZZ_AGENT_MIROFISH_MCP_DISABLE_ENV);
        assert_eq!(env_of(&cmd, BUZZ_ACP_MIROFISH_MCP_COMMAND_ENV), None);
    }

    #[test]
    fn settings_base_url_used_when_env_missing() {
        std::env::remove_var(MIROFISH_BASE_URL_ENV);
        let mut cmd = std::process::Command::new("true");
        std::env::set_var(MIROFISH_MCP_COMMAND_ENV, "/tmp/mirofish-mcp");
        apply_mirofish_mcp_env(
            &mut cmd,
            true,
            Some("http://127.0.0.1:5999".to_string()),
            |_| None,
        );
        std::env::remove_var(MIROFISH_MCP_COMMAND_ENV);
        assert_eq!(
            env_of(&cmd, MIROFISH_BASE_URL_ENV).as_deref(),
            Some("http://127.0.0.1:5999")
        );
    }
}
