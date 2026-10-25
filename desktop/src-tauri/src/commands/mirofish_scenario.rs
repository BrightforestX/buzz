use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use reqwest::Url;
use serde::Serialize;
use tauri::State;

use crate::app_state::AppState;

const FETCH_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScenarioDataStackStatus {
    pub trino_url: String,
    pub surreal_url: String,
    pub mirofish_base_url: String,
    pub trino_ready: bool,
    pub surreal_ready: bool,
    pub mirofish_ready: bool,
}

fn loopback_http_only(raw: &str, label: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{label} URL is empty"));
    }
    let url = Url::parse(trimmed).map_err(|error| format!("invalid {label} URL: {error}"))?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(format!("{label} URL must be http(s)"));
    }
    let host = url
        .host_str()
        .ok_or_else(|| format!("{label} URL missing host"))?;
    if host != "127.0.0.1" && host != "localhost" && host != "::1" {
        return Err(format!("{label} URL must target loopback (got {host})"));
    }
    Ok(trimmed.trim_end_matches('/').to_string())
}

pub(crate) fn resolve_mirofish_base_url(state: &AppState) -> String {
    if let Ok(guard) = state.mirofish_base_url_override().lock() {
        let override_url = guard.trim();
        if !override_url.is_empty() {
            return override_url.trim_end_matches('/').to_string();
        }
    }
    std::env::var("MIROFISH_BASE_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:5001".to_string())
        .trim_end_matches('/')
        .to_string()
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn resolve_zep_shim_base_url() -> String {
    env_or("ZEP_SHIM_BASE_URL", "http://127.0.0.1:8100/api/v2")
}

fn zep_record_uuid(record: &serde_json::Value) -> Option<String> {
    record
        .get("uuid")
        .or_else(|| record.get("uuid_"))
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .filter(|s| !s.is_empty())
}

async fn fetch_graph_from_zep_shim(
    client: &reqwest::Client,
    graph_id: &str,
) -> Result<serde_json::Value, String> {
    let zep_base = loopback_http_only(&resolve_zep_shim_base_url(), "zep-shim")?;
    let nodes_url = format!("{zep_base}/graph/node/graph/{graph_id}");
    let edges_url = format!("{zep_base}/graph/edge/graph/{graph_id}");
    let list_body = serde_json::json!({ "limit": 500 });

    let nodes_resp = client
        .post(&nodes_url)
        .json(&list_body)
        .send()
        .await
        .map_err(|error| format!("zep-shim node list failed: {error}"))?;
    if !nodes_resp.status().is_success() {
        return Err(format!(
            "zep-shim node list HTTP {}",
            nodes_resp.status().as_u16()
        ));
    }
    let nodes_raw: serde_json::Value = nodes_resp
        .json()
        .await
        .map_err(|error| format!("zep-shim node parse failed: {error}"))?;
    let nodes_array = nodes_raw.as_array().cloned().unwrap_or_default();

    let edges_resp = client
        .post(&edges_url)
        .json(&list_body)
        .send()
        .await
        .map_err(|error| format!("zep-shim edge list failed: {error}"))?;
    let edges_array = if edges_resp.status().is_success() {
        edges_resp
            .json::<serde_json::Value>()
            .await
            .ok()
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default()
    } else {
        vec![]
    };

    let mut nodes = Vec::with_capacity(nodes_array.len());
    for item in nodes_array {
        let Some(uuid) = zep_record_uuid(&item) else {
            continue;
        };
        nodes.push(serde_json::json!({
            "uuid": uuid,
            "name": item.get("name").and_then(|v| v.as_str()).unwrap_or(""),
            "labels": item.get("labels").cloned().unwrap_or(serde_json::json!([])),
            "summary": item.get("summary").and_then(|v| v.as_str()).unwrap_or(""),
            "attributes": item.get("attributes").cloned().unwrap_or(serde_json::json!({})),
            "created_at": item.get("created_at"),
        }));
    }

    let mut edges = Vec::with_capacity(edges_array.len());
    for item in edges_array {
        edges.push(serde_json::json!({
            "uuid": item.get("uuid_").or_else(|| item.get("uuid")),
            "name": item.get("name").and_then(|v| v.as_str()).unwrap_or(""),
            "fact": item.get("fact").and_then(|v| v.as_str()).unwrap_or(""),
            "source_node_uuid": item.get("source_node_uuid"),
            "target_node_uuid": item.get("target_node_uuid"),
            "attributes": item.get("attributes").cloned().unwrap_or(serde_json::json!({})),
        }));
    }

    Ok(serde_json::json!({
        "success": true,
        "data": {
            "graph_id": graph_id,
            "nodes": nodes,
            "edges": edges,
            "node_count": nodes.len(),
            "edge_count": edges.len(),
            "source": "zep-shim",
        }
    }))
}

async fn mirofish_graph_payload(
    client: &reqwest::Client,
    mirofish_base: &str,
    graph_id: &str,
) -> Result<serde_json::Value, String> {
    let url = format!("{mirofish_base}/api/graph/data/{graph_id}");
    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("MiroFish request failed: {error}"))?;
    let status = response.status();
    let body: serde_json::Value = response
        .json()
        .await
        .map_err(|error| format!("MiroFish response parse failed: {error}"))?;
    if !status.is_success() {
        return Err(format!(
            "MiroFish HTTP {} for GET /api/graph/data/{graph_id}",
            status.as_u16()
        ));
    }
    if body.get("success") == Some(&serde_json::Value::Bool(false)) {
        let err = body
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("MiroFish graph request failed");
        return Err(err.to_string());
    }
    let node_count = body
        .pointer("/data/nodes")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    if node_count == 0 {
        return Err("MiroFish graph has no nodes".into());
    }
    Ok(body)
}

#[tauri::command]
pub async fn fetch_mirofish_graph_data(
    state: State<'_, AppState>,
    graph_id: String,
) -> Result<serde_json::Value, String> {
    let graph_id = graph_id.trim();
    if graph_id.is_empty() {
        return Err("graphId is required".into());
    }
    let client = reqwest::Client::builder()
        .timeout(FETCH_TIMEOUT)
        .build()
        .map_err(|error| error.to_string())?;

    let mirofish_base = loopback_http_only(&resolve_mirofish_base_url(state.inner()), "MiroFish")?;
    if let Ok(body) = fetch_graph_from_zep_shim(&client, graph_id).await {
        let node_count = body
            .pointer("/data/nodes")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        if node_count > 0 {
            return Ok(body);
        }
    }
    if let Ok(body) = fetch_graph_from_surreal_snapshot(&client, graph_id).await {
        let node_count = body
            .pointer("/data/nodes")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        if node_count > 0 {
            return Ok(body);
        }
    }
    match mirofish_graph_payload(&client, &mirofish_base, graph_id).await {
        Ok(body) => Ok(body),
        Err(mirofish_err) => fetch_graph_from_zep_shim(&client, graph_id)
            .await
            .map_err(|zep_err| format!("MiroFish: {mirofish_err}; zep-shim: {zep_err}")),
    }
}

fn parse_surreal_sql_rows(body: &serde_json::Value) -> Result<Vec<serde_json::Value>, String> {
    let blocks = body
        .as_array()
        .ok_or_else(|| "SurrealDB response was not a JSON array".to_string())?;
    let mut rows = Vec::new();
    for block in blocks {
        if block.get("status").and_then(|v| v.as_str()) == Some("ERR") {
            return Err(format!(
                "SurrealDB SQL error: {}",
                block.get("result").unwrap_or(block)
            ));
        }
        if let Some(result) = block.get("result").and_then(|v| v.as_array()) {
            for item in result {
                rows.push(item.clone());
            }
        }
    }
    Ok(rows)
}

async fn post_surreal_sql(database: &str, sql: &str) -> Result<serde_json::Value, String> {
    let sql = sql.trim();
    if sql.is_empty() {
        return Err("SQL is required".into());
    }
    let base = loopback_http_only(
        &env_or("SURREALDB_URL", "http://127.0.0.1:8001"),
        "SurrealDB",
    )?;
    let ns = env_or("SCENARIO_SURREAL_NS", "sim");
    let user = env_or("SURREALDB_USER", "root");
    let pass = env_or("SURREALDB_PASS", "root");
    let url = format!("{base}/sql");
    let client = reqwest::Client::builder()
        .timeout(FETCH_TIMEOUT)
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .post(&url)
        .basic_auth(user, Some(pass))
        .header("Accept", "application/json")
        .header("surreal-ns", ns)
        .header("surreal-db", database)
        .body(sql.to_string())
        .send()
        .await
        .map_err(|error| format!("SurrealDB request failed: {error}"))?;
    let status = response.status();
    let body: serde_json::Value = response
        .json()
        .await
        .map_err(|error| format!("SurrealDB response parse failed: {error}"))?;
    if !status.is_success() {
        return Err(format!("SurrealDB HTTP {} for SQL query", status.as_u16()));
    }
    Ok(body)
}

async fn fetch_graph_from_surreal_snapshot(
    _client: &reqwest::Client,
    graph_id: &str,
) -> Result<serde_json::Value, String> {
    if !graph_id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err("invalid graphId for snapshot lookup".into());
    }
    let db = env_or("MIROFISH_EXPERIMENT_DB", "mirofish_experiments_v2");
    let sql = format!(
        "SELECT nodes, edges, source FROM graph_snapshot WHERE graph_id = '{graph_id}' LIMIT 1;"
    );
    let body = post_surreal_sql(&db, &sql).await?;
    let rows = parse_surreal_sql_rows(&body)?;
    let row = rows
        .first()
        .ok_or_else(|| format!("no graph_snapshot for {graph_id}"))?;
    let nodes = row
        .get("nodes")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let edges = row
        .get("edges")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if nodes.is_empty() {
        return Err(format!("graph_snapshot {graph_id} has no nodes"));
    }
    Ok(serde_json::json!({
        "success": true,
        "data": {
            "graph_id": graph_id,
            "nodes": nodes,
            "edges": edges,
            "node_count": nodes.len(),
            "edge_count": edges.len(),
            "source": row.get("source").and_then(|v| v.as_str()).unwrap_or("surreal-snapshot"),
        }
    }))
}

#[tauri::command]
pub async fn query_scenario_surreal(surreal_sql: String) -> Result<serde_json::Value, String> {
    let db = env_or("BUZZ_SCENARIO_SURREAL_DB", "buzz_mirofish_scenario");
    post_surreal_sql(&db, &surreal_sql).await
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScenarioMirofishExperimentRow {
    pub experiment_id: String,
    pub title: Option<String>,
    pub status: Option<String>,
    pub project_id: Option<String>,
    pub graph_id: Option<String>,
    pub simulation_id: Option<String>,
    pub report_id: Option<String>,
    pub updated_at: Option<String>,
}

fn experiment_row_from_value(value: &serde_json::Value) -> Option<ScenarioMirofishExperimentRow> {
    let experiment_id = value
        .get("experiment_id")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())?
        .to_string();
    let pick_str = |key: &str| -> Option<String> {
        value
            .get(key)
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
    };
    Some(ScenarioMirofishExperimentRow {
        experiment_id,
        title: pick_str("title"),
        status: pick_str("status"),
        project_id: pick_str("project_id"),
        graph_id: pick_str("graph_id"),
        simulation_id: pick_str("simulation_id"),
        report_id: pick_str("report_id"),
        updated_at: pick_str("updated_at"),
    })
}

#[tauri::command]
pub async fn list_scenario_mirofish_experiments(
    limit: Option<u32>,
) -> Result<Vec<ScenarioMirofishExperimentRow>, String> {
    let limit = limit.unwrap_or(50).clamp(1, 200);
    let db = env_or("MIROFISH_EXPERIMENT_DB", "mirofish_experiments_v2");
    let sql = format!(
        "SELECT experiment_id, title, status, project_id, graph_id, simulation_id, report_id, updated_at \
         FROM mirofish_experiment ORDER BY updated_at DESC LIMIT {limit};"
    );
    let body = post_surreal_sql(&db, &sql).await?;
    let rows = parse_surreal_sql_rows(&body)?;
    Ok(rows.iter().filter_map(experiment_row_from_value).collect())
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScenarioMirofishExperimentDetail {
    pub experiment: ScenarioMirofishExperimentRow,
    pub results: Option<serde_json::Value>,
}

#[tauri::command]
pub async fn get_scenario_mirofish_experiment(
    experiment_id: String,
) -> Result<ScenarioMirofishExperimentDetail, String> {
    let experiment_id = experiment_id.trim();
    if experiment_id.is_empty() {
        return Err("experimentId is required".into());
    }
    if !experiment_id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err("experimentId contains invalid characters".into());
    }
    let db = env_or("MIROFISH_EXPERIMENT_DB", "mirofish_experiments_v2");
    let sql = format!(
        "SELECT experiment_id, title, status, project_id, graph_id, simulation_id, report_id, updated_at, results_json \
         FROM mirofish_experiment WHERE experiment_id = '{experiment_id}' LIMIT 1;"
    );
    let body = post_surreal_sql(&db, &sql).await?;
    let rows = parse_surreal_sql_rows(&body)?;
    let row = rows
        .first()
        .ok_or_else(|| format!("experiment not found: {experiment_id}"))?;
    let experiment = experiment_row_from_value(row)
        .ok_or_else(|| format!("invalid experiment row: {experiment_id}"))?;
    let results = row.get("results_json").and_then(|raw| {
        if let Some(text) = raw.as_str() {
            return serde_json::from_str(text).ok();
        }
        if raw.is_object() || raw.is_array() {
            return Some(raw.clone());
        }
        None
    });
    Ok(ScenarioMirofishExperimentDetail {
        experiment,
        results,
    })
}

fn resolve_scenario_host_runner() -> Result<PathBuf, String> {
    if let Ok(raw) = std::env::var("BUZZ_SCENARIO_HOST_RUNNER") {
        let path = PathBuf::from(raw.trim());
        if path.is_file() {
            return path.canonicalize().map_err(|error| error.to_string());
        }
    }
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let candidate = manifest.join("../../scripts/buzz-scenario-run-host.sh");
    if candidate.is_file() {
        return candidate.canonicalize().map_err(|error| error.to_string());
    }
    Err("buzz-scenario-run-host.sh not found (set BUZZ_SCENARIO_HOST_RUNNER)".into())
}

fn resolve_customer_scenario_container_runner() -> Result<PathBuf, String> {
    if let Ok(raw) = std::env::var("BUZZ_CUSTOMER_SCENARIO_RUNNER") {
        let path = PathBuf::from(raw.trim());
        if path.is_file() {
            return path.canonicalize().map_err(|error| error.to_string());
        }
    }
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let candidate = manifest.join("../../scripts/buzz-customer-scenario-container.sh");
    if candidate.is_file() {
        return candidate.canonicalize().map_err(|error| error.to_string());
    }
    Err("buzz-customer-scenario-container.sh not found (set BUZZ_CUSTOMER_SCENARIO_RUNNER)".into())
}

#[tauri::command]
pub async fn run_customer_scenario_fleet() -> Result<serde_json::Value, String> {
    let runner = resolve_customer_scenario_container_runner()?;
    let output =
        tauri::async_runtime::spawn_blocking(move || Command::new("bash").arg(runner).output())
            .await
            .map_err(|error| error.to_string())?
            .map_err(|error| format!("failed to spawn customer scenario container: {error}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(format!(
            "customer scenario container exit {}: {stderr}{stdout}",
            output.status.code().unwrap_or(-1)
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let trimmed = stdout.trim();
    let json_line = trimmed
        .lines()
        .rev()
        .find(|line| line.trim_start().starts_with('{'))
        .unwrap_or(trimmed);
    let parsed: serde_json::Value = serde_json::from_str(json_line.trim())
        .map_err(|error| format!("customer fleet JSON parse failed: {error}; output: {stdout}"))?;
    Ok(parsed)
}

#[tauri::command]
pub async fn run_scenario_mirofish_experiment_fixture() -> Result<serde_json::Value, String> {
    let runner = resolve_scenario_host_runner()?;
    let output =
        tauri::async_runtime::spawn_blocking(move || Command::new("bash").arg(runner).output())
            .await
            .map_err(|error| error.to_string())?
            .map_err(|error| format!("failed to spawn scenario runner: {error}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(format!(
            "scenario runner exit {}: {stderr}{stdout}",
            output.status.code().unwrap_or(-1)
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim())
        .map_err(|error| format!("scenario runner JSON parse failed: {error}; output: {stdout}"))?;
    Ok(parsed)
}

async fn probe_url(url: &str, path: &str) -> bool {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(3))
        .build()
    {
        Ok(client) => client,
        Err(_) => return false,
    };
    client
        .get(format!("{}{}", url.trim_end_matches('/'), path))
        .send()
        .await
        .map(|response| response.status().is_success())
        .unwrap_or(false)
}

#[tauri::command]
pub async fn get_scenario_data_stack_status(
    state: State<'_, AppState>,
) -> Result<ScenarioDataStackStatus, String> {
    let trino_url = env_or("TRINO_HOST", "http://127.0.0.1:8080");
    let surreal_url = env_or("SURREALDB_URL", "http://127.0.0.1:8001");
    let mirofish_base_url = resolve_mirofish_base_url(state.inner());

    let trino_ready = if let Ok(trino) = loopback_http_only(&trino_url, "Trino") {
        probe_url(&trino, "/v1/info").await
    } else {
        false
    };

    let surreal_ready = if let Ok(surreal) = loopback_http_only(&surreal_url, "SurrealDB") {
        probe_url(&surreal, "/health").await
    } else {
        false
    };

    let mirofish_ready = if let Ok(mf) = loopback_http_only(&mirofish_base_url, "MiroFish") {
        probe_url(&mf, "/health").await
    } else {
        false
    };

    Ok(ScenarioDataStackStatus {
        trino_url,
        surreal_url,
        mirofish_base_url,
        trino_ready,
        surreal_ready,
        mirofish_ready,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loopback_http_only_accepts_localhost() {
        assert!(loopback_http_only("http://127.0.0.1:8001", "SurrealDB").is_ok());
        assert!(loopback_http_only("http://localhost:5001/", "MiroFish").is_ok());
    }

    #[test]
    fn loopback_http_only_rejects_remote_host() {
        let err = loopback_http_only("http://example.com:5001", "MiroFish").unwrap_err();
        assert!(err.contains("loopback"));
    }

    #[test]
    fn parse_surreal_sql_rows_extracts_result_array() {
        let body = serde_json::json!([
            {"status": "OK", "result": [{"experiment_id": "exp_1"}]}
        ]);
        let rows = parse_surreal_sql_rows(&body).expect("parse");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["experiment_id"], "exp_1");
    }

    #[test]
    fn experiment_row_from_value_requires_id() {
        assert!(experiment_row_from_value(&serde_json::json!({"title": "x"})).is_none());
        let row =
            experiment_row_from_value(&serde_json::json!({"experiment_id": "exp_a"})).expect("row");
        assert_eq!(row.experiment_id, "exp_a");
    }
}
