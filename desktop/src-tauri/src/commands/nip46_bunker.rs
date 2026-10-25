//! Local HTTP NIP-46 bunker for glasses → Buzz voice (kinds 9 + 22242 only).

use std::collections::HashSet;
use std::sync::{Arc, Mutex};

use axum::{
    extract::State as AxumState,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use buzz_nip46_pkg::{sign_unsigned_json, BunkerSignError, SignedEventJson, UnsignedEventJson};
use nostr::prelude::*;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;

use crate::app_state::AppState;
use crate::relay::{relay_api_base_url_with_override, submit_signed_event_at_with_keys};

const DEFAULT_PORT: u16 = 9476;

#[derive(Clone)]
struct BunkerHttpState {
    app_handle: AppHandle,
    token: String,
    allowed_clients: Arc<Mutex<HashSet<String>>>,
}

#[derive(Serialize)]
pub struct Nip46BunkerStatus {
    pub running: bool,
    pub port: u16,
    pub owner_pubkey: Option<String>,
    pub bunker_url: Option<String>,
    pub allowed_clients: Vec<String>,
}

pub struct GlassesBunkerHandle {
    cancel: Mutex<Option<CancellationToken>>,
    port: Mutex<u16>,
    token: Mutex<String>,
    allowed_clients: Arc<Mutex<HashSet<String>>>,
}

impl GlassesBunkerHandle {
    pub fn new() -> Self {
        Self {
            cancel: Mutex::new(None),
            port: Mutex::new(DEFAULT_PORT),
            token: Mutex::new(uuid::Uuid::new_v4().to_string()),
            allowed_clients: Arc::new(Mutex::new(HashSet::new())),
        }
    }
}

#[derive(Deserialize)]
struct SignEventRequest {
    client_pubkey: String,
    event: UnsignedEventJson,
}

#[derive(Deserialize)]
struct PublishEventRequest {
    event: SignedEventJson,
}

#[derive(Deserialize)]
struct QueryRequest {
    filters: Vec<serde_json::Value>,
}

fn authorize(headers: &HeaderMap, token: &str) -> bool {
    let auth = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    auth == format!("Bearer {token}")
}

fn client_allowed(state: &BunkerHttpState, client_pubkey: &str) -> bool {
    let key = client_pubkey.trim().to_lowercase();
    state
        .allowed_clients
        .lock()
        .map(|set| set.contains(&key))
        .unwrap_or(false)
}

async fn status_handler(AxumState(state): AxumState<BunkerHttpState>) -> impl IntoResponse {
    let app_state = state.app_handle.state::<AppState>();
    let owner = app_state
        .signing_keys()
        .map(|k| k.public_key().to_hex())
        .ok();
    let allowed = state
        .allowed_clients
        .lock()
        .map(|s| s.iter().cloned().collect::<Vec<_>>())
        .unwrap_or_default();
    Json(serde_json::json!({
        "running": true,
        "owner_pubkey": owner,
        "allowed_clients": allowed,
    }))
}

async fn sign_event_handler(
    AxumState(state): AxumState<BunkerHttpState>,
    headers: HeaderMap,
    Json(body): Json<SignEventRequest>,
) -> Result<Json<SignedEventJson>, (StatusCode, String)> {
    if !authorize(&headers, &state.token) {
        return Err((StatusCode::UNAUTHORIZED, "unauthorized".into()));
    }
    let client = body.client_pubkey.trim().to_lowercase();
    if !client_allowed(&state, &client) {
        return Err((StatusCode::FORBIDDEN, "client not allowlisted".into()));
    }
    let app_state = state.app_handle.state::<AppState>();
    let keys = app_state
        .signing_keys()
        .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e))?;
    match sign_unsigned_json(&keys, &body.event, true) {
        Ok(signed) => Ok(Json(signed)),
        Err(BunkerSignError::KindNotAllowed(k)) => {
            Err((StatusCode::FORBIDDEN, format!("kind {k} not allowed")))
        }
        Err(e) => Err((StatusCode::BAD_REQUEST, e.to_string())),
    }
}

async fn publish_event_handler(
    AxumState(state): AxumState<BunkerHttpState>,
    headers: HeaderMap,
    Json(body): Json<PublishEventRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if !authorize(&headers, &state.token) {
        return Err((StatusCode::UNAUTHORIZED, "unauthorized".into()));
    }
    let app_state = state.app_handle.state::<AppState>();
    let keys = app_state
        .signing_keys()
        .map_err(|e| (StatusCode::SERVICE_UNAVAILABLE, e))?;
    let event = Event::from_json(serde_json::to_string(&body.event).unwrap_or_default())
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("invalid event: {e}")))?;
    if event.pubkey != keys.public_key() {
        return Err((StatusCode::FORBIDDEN, "event pubkey mismatch".into()));
    }
    let api = relay_api_base_url_with_override(&app_state);
    let result = submit_signed_event_at_with_keys(&event, &app_state, &api, &keys)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, e))?;
    Ok(Json(serde_json::json!({
        "event_id": result.event_id,
        "accepted": result.accepted,
        "message": result.message,
    })))
}

async fn query_handler(
    AxumState(state): AxumState<BunkerHttpState>,
    headers: HeaderMap,
    Json(body): Json<QueryRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if !authorize(&headers, &state.token) {
        return Err((StatusCode::UNAUTHORIZED, "unauthorized".into()));
    }
    let app_state = state.app_handle.state::<AppState>();
    let api = relay_api_base_url_with_override(&app_state);
    let events = crate::relay::query_relay_at(&app_state, &api, &body.filters)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, e))?;
    let json_events: Vec<serde_json::Value> = events
        .iter()
        .filter_map(|event| serde_json::from_str(&event.as_json()).ok())
        .collect();
    Ok(Json(serde_json::json!({ "events": json_events })))
}

fn build_router(state: BunkerHttpState) -> Router {
    Router::new()
        .route("/nip46/status", get(status_handler))
        .route("/nip46/sign_event", post(sign_event_handler))
        .route("/nip46/publish_event", post(publish_event_handler))
        .route("/nip46/query", post(query_handler))
        .with_state(state)
}

#[tauri::command]
pub async fn nip46_start_glasses_bunker(
    app_handle: AppHandle,
    handle: State<'_, GlassesBunkerHandle>,
    port: Option<u16>,
) -> Result<Nip46BunkerStatus, String> {
    let port = port.unwrap_or(DEFAULT_PORT);
    let token = {
        let mut t = handle.token.lock().map_err(|e| e.to_string())?;
        if t.is_empty() {
            *t = uuid::Uuid::new_v4().to_string();
        }
        t.clone()
    };
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

    let http_state = BunkerHttpState {
        app_handle: app_handle.clone(),
        token: token.clone(),
        allowed_clients: handle.allowed_clients.clone(),
    };
    let router = build_router(http_state);
    let listener = TcpListener::bind(format!("127.0.0.1:{port}"))
        .await
        .map_err(|e| format!("bind bunker port {port}: {e}"))?;
    let child = cancel.clone();
    tauri::async_runtime::spawn(async move {
        axum::serve(listener, router)
            .with_graceful_shutdown(async move {
                child.cancelled().await;
            })
            .await
            .ok();
    });

    nip46_get_glasses_bunker_status(app_handle, handle)
}

#[tauri::command]
pub async fn nip46_stop_glasses_bunker(
    handle: State<'_, GlassesBunkerHandle>,
) -> Result<(), String> {
    let mut c = handle.cancel.lock().map_err(|e| e.to_string())?;
    if let Some(prev) = c.take() {
        prev.cancel();
    }
    Ok(())
}

#[tauri::command]
pub fn nip46_allow_glasses_client(
    handle: State<'_, GlassesBunkerHandle>,
    client_pubkey: String,
) -> Result<Vec<String>, String> {
    let key = client_pubkey.trim().to_lowercase();
    if key.len() != 64 || !key.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("client pubkey must be 64-char hex".into());
    }
    let mut set = handle.allowed_clients.lock().map_err(|e| e.to_string())?;
    set.insert(key);
    Ok(set.iter().cloned().collect())
}

#[tauri::command]
pub fn nip46_get_glasses_bunker_status(
    app_handle: AppHandle,
    handle: State<'_, GlassesBunkerHandle>,
) -> Result<Nip46BunkerStatus, String> {
    let port = *handle.port.lock().map_err(|e| e.to_string())?;
    let running = handle.cancel.lock().map_err(|e| e.to_string())?.is_some();
    let allowed = handle
        .allowed_clients
        .lock()
        .map_err(|e| e.to_string())?
        .iter()
        .cloned()
        .collect();
    let owner = app_handle
        .state::<AppState>()
        .signing_keys()
        .map(|k| k.public_key().to_hex())
        .ok();
    let token = handle.token.lock().map_err(|e| e.to_string())?.clone();
    let bunker_url = if running {
        Some(format!("bunker://127.0.0.1:{port}?token={token}"))
    } else {
        None
    };
    Ok(Nip46BunkerStatus {
        running,
        port,
        owner_pubkey: owner,
        bunker_url,
        allowed_clients: allowed,
    })
}
