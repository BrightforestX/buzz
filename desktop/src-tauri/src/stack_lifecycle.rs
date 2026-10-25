//! Idle sleep/wake integration: activity ledger + relay probe + auto-wake on launch.

use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use chrono::Utc;
use serde_json::json;
use tauri::{AppHandle, Emitter};

static WAKE_IN_FLIGHT: AtomicBool = AtomicBool::new(false);
static LAST_ACTIVITY_RECORD: std::sync::Mutex<Option<std::time::Instant>> =
    std::sync::Mutex::new(None);

fn buzz_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn activity_file() -> PathBuf {
    buzz_root().join(".local/stack-activity.json")
}

fn stack_auto_wake_enabled() -> bool {
    match std::env::var("STACK_AUTO_WAKE") {
        Ok(v) => !matches!(v.as_str(), "0" | "false" | "no"),
        Err(_) => true,
    }
}

pub fn record_activity(source: &str) {
    if source == "health_monitor" {
        return;
    }
    if let Ok(mut guard) = LAST_ACTIVITY_RECORD.lock() {
        if let Some(last) = *guard {
            if last.elapsed() < Duration::from_secs(60) && source != "desktop" {
                return;
            }
        }
        *guard = Some(std::time::Instant::now());
    }

    let path = activity_file();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let payload = json!({
        "last_activity": ts,
        "last_source": source,
    });
    if let Ok(bytes) = serde_json::to_vec_pretty(&payload) {
        if let Ok(mut file) = atomic_write_file::AtomicWriteFile::open(&path) {
            let _ = file.write_all(&bytes);
            let _ = file.commit();
        }
    }
}

const RELAY_PROBE_URL: &str = "https://relay.pathx.ai/";

async fn relay_http_reachable_async() -> bool {
    match reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
    {
        Ok(client) => client
            .get(RELAY_PROBE_URL)
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false),
        Err(_) => false,
    }
}

fn ontology_stack_root() -> PathBuf {
    buzz_root()
        .join("../../infrastructure/digitalocean/ontology-stack")
        .canonicalize()
        .unwrap_or_else(|_| buzz_root().join("../../infrastructure/digitalocean/ontology-stack"))
}

fn spawn_wake_workflow() -> bool {
    let temporal_root = ontology_stack_root().join("temporal");
    if !temporal_root.join("pyproject.toml").exists() {
        return false;
    }
    let status = Command::new("uv")
        .args(["run", "stack-lifecycle-client", "wake"])
        .current_dir(&temporal_root)
        .env("BUZZ_ROOT", buzz_root())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    status.map(|s| s.success()).unwrap_or(false)
}

fn spawn_wake_shell() {
    let script = buzz_root().join("scripts/stack-wake.sh");
    if !script.exists() {
        eprintln!("stack_lifecycle: missing {}", script.display());
        return;
    }
    let _ = Command::new("bash")
        .arg(&script)
        .env("BUZZ_ROOT", buzz_root())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

fn start_wake(app: &AppHandle) {
    if WAKE_IN_FLIGHT.swap(true, Ordering::SeqCst) {
        return;
    }
    let _ = app.emit("stack-waking", ());
    if !spawn_wake_workflow() {
        spawn_wake_shell();
    }
    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        for _ in 0..60 {
            tokio::time::sleep(Duration::from_secs(30)).await;
            if relay_http_reachable_async().await {
                let _ = handle.emit("stack-awake", ());
                record_activity("relay_post");
                WAKE_IN_FLIGHT.store(false, Ordering::SeqCst);
                return;
            }
        }
        let _ = handle.emit("stack-wake-timeout", ());
        WAKE_IN_FLIGHT.store(false, Ordering::SeqCst);
    });
}

pub fn on_app_start(app: &AppHandle) {
    record_activity("desktop");
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        if relay_http_reachable_async().await {
            return;
        }
        if stack_auto_wake_enabled() {
            start_wake(&app);
        }
    });
}

#[tauri::command]
pub fn stack_record_activity(source: String) -> Result<(), String> {
    record_activity(&source);
    Ok(())
}

#[tauri::command]
pub async fn stack_ensure_awake(app: AppHandle) -> Result<bool, String> {
    record_activity("desktop");
    if relay_http_reachable_async().await {
        return Ok(true);
    }
    if stack_auto_wake_enabled() {
        start_wake(&app);
    }
    Ok(false)
}

#[tauri::command]
pub async fn stack_relay_status() -> Result<bool, String> {
    Ok(relay_http_reachable_async().await)
}
