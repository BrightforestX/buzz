use buzz_cli::workflows::{cmd_create_workflow, cmd_trigger_workflow, BuzzClient};
use nostr::Keys;
use rmcp::ErrorData;
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
pub struct CreateWorkflowParams {
    pub channel_id: String,
    pub yaml_definition: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct TriggerWorkflowParams {
    pub workflow_id: String,
    pub inputs_json: Option<String>,
}

fn client_from_env() -> Result<BuzzClient, String> {
    let relay_url = std::env::var("BUZZ_RELAY_URL")
        .map_err(|_| "BUZZ_RELAY_URL is required for workflow tools".to_string())?;
    let private_key = std::env::var("BUZZ_PRIVATE_KEY")
        .map_err(|_| "BUZZ_PRIVATE_KEY is required for workflow tools".to_string())?;
    let keys = Keys::parse(&private_key).map_err(|e| format!("invalid BUZZ_PRIVATE_KEY: {e}"))?;
    let auth_tag_json = std::env::var("BUZZ_AUTH_TAG")
        .ok()
        .filter(|s| !s.is_empty());
    let auth_tag = auth_tag_json
        .as_ref()
        .map(|json| buzz_sdk::nip_oa::parse_auth_tag(json))
        .transpose()
        .map_err(|e| format!("BUZZ_AUTH_TAG is malformed: {e}"))?;
    BuzzClient::new(relay_url, keys, auth_tag, auth_tag_json)
        .map_err(|e| format!("failed to create Buzz client: {e}"))
}

pub async fn create_workflow(p: CreateWorkflowParams) -> Result<String, ErrorData> {
    buzz_workflow::WorkflowEngine::parse_yaml(&p.yaml_definition)
        .map(|_| ())
        .map_err(|e| ErrorData::invalid_params(format!("invalid workflow YAML: {e}"), None))?;
    let client = client_from_env().map_err(|e| ErrorData::invalid_params(e, None))?;
    cmd_create_workflow(&client, &p.channel_id, &p.yaml_definition)
        .await
        .map_err(|e| ErrorData::internal_error(format!("create_workflow failed: {e}"), None))?;
    Ok("workflow created (see buzz CLI stdout for workflow_id)".to_string())
}

pub async fn trigger_workflow(p: TriggerWorkflowParams) -> Result<String, ErrorData> {
    let client = client_from_env().map_err(|e| ErrorData::invalid_params(e, None))?;
    cmd_trigger_workflow(&client, &p.workflow_id, p.inputs_json.as_deref())
        .await
        .map_err(|e| ErrorData::internal_error(format!("trigger_workflow failed: {e}"), None))?;
    Ok("workflow triggered".to_string())
}
