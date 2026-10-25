//! Loopback HTTP shim for local Lean 4 (`lean` / `lake`) — formal verify dev path.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;

use axum::{
    extract::State as AxumState,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tauri::State;
use tokio::net::TcpListener;
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

const DEFAULT_PORT: u16 = 9477;
const RUN_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone)]
struct Lean4HttpState {
    token: Option<String>,
    default_workspace: PathBuf,
}

#[derive(Serialize)]
pub struct Lean4LocalStatus {
    pub running: bool,
    pub port: u16,
    pub base_url: Option<String>,
    pub default_workspace: String,
    pub lean_on_path: bool,
}

pub struct Lean4LocalHandle {
    cancel: Mutex<Option<CancellationToken>>,
    port: Mutex<u16>,
    token: Mutex<Option<String>>,
}

impl Lean4LocalHandle {
    pub fn new() -> Self {
        Self {
            cancel: Mutex::new(None),
            port: Mutex::new(DEFAULT_PORT),
            token: Mutex::new(
                std::env::var("BUZZ_LEAN4_TOKEN")
                    .ok()
                    .filter(|s| !s.is_empty()),
            ),
        }
    }
}

fn default_workspace() -> PathBuf {
    if let Ok(raw) = std::env::var("LEAN_WORKSPACE") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../../06-pipelines/formal/lean")
}

fn authorize(headers: &HeaderMap, token: &Option<String>) -> bool {
    let Some(expected) = token else {
        return true;
    };
    let auth = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    auth == format!("Bearer {expected}")
}

async fn run_command(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
) -> Result<(i32, String, String), String> {
    let mut cmd = Command::new(program);
    cmd.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let child = cmd.spawn().map_err(|e| format!("spawn {program}: {e}"))?;
    let output = tokio::time::timeout(RUN_TIMEOUT, child.wait_with_output())
        .await
        .map_err(|_| format!("{program} timed out after {}s", RUN_TIMEOUT.as_secs()))?
        .map_err(|e| format!("wait {program}: {e}"))?;
    let code = output.status.code().unwrap_or(-1);
    Ok((
        code,
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    ))
}

async fn health_handler() -> impl IntoResponse {
    Json(serde_json::json!({ "ok": true, "service": "buzz-lean4-local" }))
}

async fn version_handler() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let (code, stdout, stderr) = run_command("lean", &["--version"], None)
        .await
        .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e))?;
    Ok(Json(serde_json::json!({
        "exit_code": code,
        "stdout": stdout.trim(),
        "stderr": stderr.trim(),
    })))
}

#[derive(Deserialize)]
struct CheckRequest {
    source: String,
    #[serde(default)]
    filename: Option<String>,
}

async fn check_handler(
    AxumState(state): AxumState<Lean4HttpState>,
    headers: HeaderMap,
    Json(body): Json<CheckRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if !authorize(&headers, &state.token) {
        return Err((StatusCode::UNAUTHORIZED, "unauthorized".into()));
    }
    if body.source.trim().is_empty() {
        return Err((StatusCode::BAD_REQUEST, "source is required".into()));
    }
    let dir =
        tempfile::tempdir().map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let name = body.filename.as_deref().unwrap_or("Snippet.lean").trim();
    let file = dir.path().join(if name.ends_with(".lean") {
        name.to_string()
    } else {
        format!("{name}.lean")
    });
    std::fs::write(&file, &body.source)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let (code, stdout, stderr) =
        run_command("lean", &[file.to_string_lossy().as_ref()], Some(dir.path()))
            .await
            .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e))?;
    Ok(Json(serde_json::json!({
        "ok": code == 0,
        "exit_code": code,
        "stdout": stdout,
        "stderr": stderr,
    })))
}

#[derive(Deserialize)]
struct BuildRequest {
    workspace: Option<String>,
}

async fn build_handler(
    AxumState(state): AxumState<Lean4HttpState>,
    headers: HeaderMap,
    Json(body): Json<BuildRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if !authorize(&headers, &state.token) {
        return Err((StatusCode::UNAUTHORIZED, "unauthorized".into()));
    }
    let workspace = body
        .workspace
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| state.default_workspace.clone());
    if !workspace.is_dir() {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("workspace not found: {}", workspace.display()),
        ));
    }
    let (code, stdout, stderr) = run_command("lake", &["build"], Some(&workspace))
        .await
        .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e))?;
    Ok(Json(serde_json::json!({
        "ok": code == 0,
        "exit_code": code,
        "workspace": workspace.to_string_lossy(),
        "stdout": stdout,
        "stderr": stderr,
    })))
}

fn build_router(state: Lean4HttpState) -> Router {
    Router::new()
        .route("/lean4/health", get(health_handler))
        .route("/lean4/version", get(version_handler))
        .route("/lean4/check", post(check_handler))
        .route("/lean4/build", post(build_handler))
        .with_state(state)
}

fn lean_on_path() -> bool {
    std::process::Command::new("lean")
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

#[tauri::command]
pub async fn lean4_start_local_server(
    handle: State<'_, Lean4LocalHandle>,
    port: Option<u16>,
) -> Result<Lean4LocalStatus, String> {
    let port = port.unwrap_or(DEFAULT_PORT);
    {
        let mut c = handle.cancel.lock().map_err(|e| e.to_string())?;
        if let Some(prev) = c.take() {
            prev.cancel();
        }
    }
    let cancel = CancellationToken::new();
    {
        let mut c = handle.cancel.lock().map_err(|e| e.to_string())?;
        *c = Some(cancel.clone());
    }
    {
        let mut p = handle.port.lock().map_err(|e| e.to_string())?;
        *p = port;
    }

    let token = handle.token.lock().map_err(|e| e.to_string())?.clone();
    let workspace = default_workspace();
    let http_state = Lean4HttpState {
        token,
        default_workspace: workspace.clone(),
    };
    let router = build_router(http_state);
    let listener = TcpListener::bind(format!("127.0.0.1:{port}"))
        .await
        .map_err(|e| format!("bind lean4 port {port}: {e}"))?;
    let child = cancel.clone();
    tauri::async_runtime::spawn(async move {
        axum::serve(listener, router)
            .with_graceful_shutdown(async move {
                child.cancelled().await;
            })
            .await
            .ok();
    });

    lean4_get_local_status(handle)
}

#[tauri::command]
pub async fn lean4_stop_local_server(handle: State<'_, Lean4LocalHandle>) -> Result<(), String> {
    let mut c = handle.cancel.lock().map_err(|e| e.to_string())?;
    if let Some(prev) = c.take() {
        prev.cancel();
    }
    Ok(())
}

#[tauri::command]
pub fn lean4_get_local_status(
    handle: State<'_, Lean4LocalHandle>,
) -> Result<Lean4LocalStatus, String> {
    let port = *handle.port.lock().map_err(|e| e.to_string())?;
    let running = handle.cancel.lock().map_err(|e| e.to_string())?.is_some();
    let workspace = default_workspace();
    Ok(Lean4LocalStatus {
        running,
        port,
        base_url: if running {
            Some(format!("http://127.0.0.1:{port}"))
        } else {
            None
        },
        default_workspace: workspace.to_string_lossy().into_owned(),
        lean_on_path: lean_on_path(),
    })
}
