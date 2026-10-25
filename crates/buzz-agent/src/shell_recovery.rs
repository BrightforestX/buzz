//! Recover Buzz publish commands when models emit them as assistant text or
//! under hallucinated tool names instead of the registered MCP `shell` tool.
//!
//! Kimi K2.x via OpenAI-compatible routes often embeds tool calls in the
//! content stream (`<|tool_call_argument_begin|>{...}`) or prints markdown
//! `buzz messages send` lines with `stop=EndTurn` and an empty `tool_calls`
//! array. Without recovery those turns never reach `buzz-dev-mcp__shell`.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;

use serde_json::{json, Map, Value};

use crate::mcp::McpRegistry;
use crate::types::{LlmResponse, ToolCall};

const KIMI_ARG_MARKERS: &[&str] = &["tool_call_argument_begin|>", "<|message|>"];

// #region agent log
fn agent_debug_log(hypothesis_id: &str, location: &str, message: &str, data: Value) {
    let path = std::env::var("BUZZ_AGENT_DEBUG_LOG").ok();
    if path.is_none() {
        return;
    }
    let payload = json!({
        "sessionId": "7a21c8",
        "hypothesisId": hypothesis_id,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0),
    });
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path.unwrap())
    {
        let _ = writeln!(file, "{}", payload);
    }
}
// #endregion

/// Normalize provider output so publish-shaped shell invocations execute.
pub fn recover_shell_tool_calls(response: &mut LlmResponse, mcp: &McpRegistry) {
    let shell = mcp.find_bare_tool("shell");
    if shell.is_none() {
        return;
    }
    let shell = shell.unwrap();

    let text_commands = extract_publish_commands(&response.text);
    let before_tool_calls = response.tool_calls.len();
    let before_empty_shells = response
        .tool_calls
        .iter()
        .filter(|call| is_empty_shell_call(call, &shell))
        .count();

    if !response.tool_calls.is_empty() {
        for call in &mut response.tool_calls {
            coerce_call_to_shell(call, &shell, mcp);
        }
        response
            .tool_calls
            .retain(|call| !is_empty_shell_call(call, &shell));

        let existing: BTreeSet<String> = response
            .tool_calls
            .iter()
            .filter_map(|call| {
                command_from_tool_args(&call.arguments).and_then(normalize_buzz_command)
            })
            .collect();
        let mut recovered_from_text = 0usize;
        for (i, command) in text_commands.iter().enumerate() {
            if existing.contains(command) {
                continue;
            }
            response.tool_calls.push(ToolCall {
                provider_id: format!("recovered-shell-text-{i}"),
                name: shell.clone(),
                arguments: json!({ "command": command }),
                provider_extra: Map::new(),
            });
            recovered_from_text += 1;
        }
        if recovered_from_text > 0 {
            response.text = strip_recovered_publish_text(&response.text);
        }

        // #region agent log
        agent_debug_log(
            "B",
            "shell_recovery.rs:recover_shell_tool_calls",
            "merged text recovery with non-empty tool_calls",
            json!({
                "beforeToolCalls": before_tool_calls,
                "beforeEmptyShells": before_empty_shells,
                "afterToolCalls": response.tool_calls.len(),
                "textCommands": text_commands.len(),
                "recoveredFromText": recovered_from_text,
            }),
        );
        // #endregion
        return;
    }

    if text_commands.is_empty() {
        // #region agent log
        agent_debug_log(
            "B",
            "shell_recovery.rs:recover_shell_tool_calls",
            "no publish commands recovered",
            json!({
                "beforeToolCalls": before_tool_calls,
                "beforeEmptyShells": before_empty_shells,
            }),
        );
        // #endregion
        return;
    }

    let cleaned = strip_recovered_publish_text(&response.text);
    response.text = cleaned;
    response.tool_calls = text_commands
        .into_iter()
        .enumerate()
        .map(|(i, command)| ToolCall {
            provider_id: format!("recovered-shell-{i}"),
            name: shell.clone(),
            arguments: json!({ "command": command }),
            provider_extra: Map::new(),
        })
        .collect();

    // #region agent log
    agent_debug_log(
        "B",
        "shell_recovery.rs:recover_shell_tool_calls",
        "recovered publish commands from assistant text",
        json!({
            "beforeToolCalls": before_tool_calls,
            "afterToolCalls": response.tool_calls.len(),
        }),
    );
    // #endregion
}

fn is_empty_shell_call(call: &ToolCall, shell: &str) -> bool {
    let bare = call
        .name
        .rsplit_once("__")
        .map(|(_, b)| b)
        .unwrap_or(call.name.as_str());
    let is_shell = call.name == shell || bare == "shell" || looks_like_shell_alias(&call.name);
    is_shell && command_from_tool_args(&call.arguments).is_none()
}

fn coerce_call_to_shell(call: &mut ToolCall, shell: &str, mcp: &McpRegistry) {
    if mcp.has(&call.name) && !mcp.is_hook(&call.name) {
        return;
    }
    if !looks_like_shell_alias(&call.name) {
        return;
    }
    if let Some(command) =
        command_from_tool_args(&call.arguments).and_then(|c| normalize_buzz_command(c))
    {
        tracing::info!("coerced hallucinated tool {:?} → {}", call.name, shell);
        call.name = shell.to_string();
        call.arguments = json!({ "command": command });
    }
}

fn looks_like_shell_alias(name: &str) -> bool {
    let bare = name.rsplit_once("__").map(|(_, b)| b).unwrap_or(name);
    let bare = bare.strip_prefix("functions.").unwrap_or(bare);
    matches!(
        bare,
        "shell" | "execute_bash" | "bash" | "buzz-cli" | "buzz" | "Buzz" | "BuzzCLI"
    ) || bare.contains("bash")
        || bare.contains("shell")
        || bare.ends_with("___buzz")
        || bare.contains("buzz_messages_send")
        || bare.contains("messages_send")
        || bare.contains("buzz-messages-send")
}

pub(crate) fn extract_publish_commands(text: &str) -> Vec<String> {
    let mut seen = BTreeMap::new();
    for cmd in extract_kimi_commands(text)
        .chain(extract_markdown_bash_commands(text))
        .chain(extract_inline_buzz_send_lines(text))
        .filter_map(normalize_buzz_command)
    {
        seen.insert(cmd, ());
    }
    seen.into_keys().collect()
}

fn extract_kimi_commands(text: &str) -> impl Iterator<Item = String> + '_ {
    let mut cmds = Vec::new();
    for marker in KIMI_ARG_MARKERS {
        for tail in text.split(marker).skip(1) {
            let json_str = tail.split("<|").next().map(str::trim);
            if let Some(json_str) = json_str {
                if let Ok(v) = serde_json::from_str::<Value>(json_str) {
                    if let Some(cmd) = command_from_tool_args(&v) {
                        cmds.push(cmd);
                    }
                }
            }
        }
    }
    cmds.into_iter()
}

fn extract_markdown_bash_commands(text: &str) -> impl Iterator<Item = String> + '_ {
    let mut cmds = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("```") {
        let after_fence = &rest[start + 3..];
        let lang_end = after_fence.find('\n').unwrap_or(after_fence.len());
        let lang = after_fence[..lang_end].trim();
        let body_start = if lang_end < after_fence.len() {
            lang_end + 1
        } else {
            lang_end
        };
        let body_region = &after_fence[body_start..];
        if let Some(close) = body_region.find("```") {
            let body = body_region[..close].trim();
            if lang.is_empty() || lang == "bash" || lang == "sh" || lang == "shell" {
                for line in body.lines() {
                    let line = line.trim();
                    if line.contains("messages send") || line.starts_with("buzz ") {
                        cmds.push(line.to_string());
                    }
                }
            }
            rest = &body_region[close + 3..];
        } else {
            break;
        }
    }
    cmds.into_iter()
}

fn extract_inline_buzz_send_lines(text: &str) -> impl Iterator<Item = String> + '_ {
    text.lines()
        .map(str::trim)
        .filter(|line| line.starts_with("buzz messages send"))
        .map(str::to_string)
        .collect::<Vec<_>>()
        .into_iter()
}

fn command_from_tool_args(args: &Value) -> Option<String> {
    const KEYS: &[&str] = &["command", "bash_command", "cmd", "script"];
    for key in KEYS {
        if let Some(s) = args.get(key).and_then(Value::as_str) {
            if !s.trim().is_empty() {
                return Some(s.trim().to_string());
            }
        }
    }
    if let (Some(channel), Some(content)) = (
        args.get("channel").and_then(Value::as_str),
        args.get("content").and_then(Value::as_str),
    ) {
        let reply_to = args
            .get("reply_to")
            .or_else(|| args.get("replyTo"))
            .and_then(Value::as_str);
        return Some(build_buzz_send_command(channel, content, reply_to));
    }
    None
}

fn build_buzz_send_command(channel: &str, content: &str, reply_to: Option<&str>) -> String {
    let escaped = content.replace('\\', "\\\\").replace('"', "\\\"");
    let mut cmd = format!("buzz messages send --channel {channel}");
    if let Some(rt) = reply_to {
        if !rt.is_empty() {
            cmd.push_str(&format!(" --reply-to {rt}"));
        }
    }
    cmd.push_str(&format!(" --content \"{escaped}\""));
    cmd
}

fn normalize_buzz_command(raw: String) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let cmd =
        if trimmed.starts_with("buzz messages send") || trimmed.starts_with("buzz reactions add") {
            trimmed.to_string()
        } else if trimmed.starts_with("messages send") || trimmed.starts_with("reactions add") {
            format!("buzz {trimmed}")
        } else if trimmed.contains("messages send") || trimmed.contains("reactions add") {
            // `sh -c "buzz messages send ..."` and similar wrappers.
            trimmed.to_string()
        } else {
            return None;
        };
    if cmd.contains("messages send") || cmd.contains("reactions add") {
        Some(cmd)
    } else {
        None
    }
}

fn next_kimi_arg_marker(text: &str) -> Option<(usize, usize)> {
    KIMI_ARG_MARKERS
        .iter()
        .filter_map(|marker| text.find(marker).map(|pos| (pos, marker.len())))
        .min_by_key(|(pos, _)| *pos)
}

fn strip_recovered_publish_text(text: &str) -> String {
    let mut out = String::new();
    let mut cursor = 0;
    while cursor < text.len() {
        if let Some((rel, marker_len)) = next_kimi_arg_marker(&text[cursor..]) {
            let abs = cursor + rel;
            out.push_str(text[cursor..abs].trim_end());
            let tail = &text[abs + marker_len..];
            if let Some(end_rel) = tail.find("<|redacted_tool_call_end") {
                cursor = abs + marker_len + end_rel + "<|redacted_tool_call_end".len();
                while cursor < text.len() && text.as_bytes().get(cursor) != Some(&b'<') {
                    cursor += 1;
                }
            } else if let Some(end_rel) = tail.find("tool_call_end") {
                cursor = abs + marker_len + end_rel;
                while cursor < text.len() && text.as_bytes().get(cursor) != Some(&b'<') {
                    cursor += 1;
                }
            } else {
                break;
            }
            continue;
        }
        out.push_str(&text[cursor..]);
        break;
    }

    // Drop markdown bash fences that only carried a publish command.
    let mut cleaned = String::new();
    let mut rest = out.as_str();
    while let Some(start) = rest.find("```") {
        cleaned.push_str(rest[..start].trim_end());
        let after_fence = &rest[start + 3..];
        let lang_end = after_fence.find('\n').unwrap_or(after_fence.len());
        let lang = after_fence[..lang_end].trim();
        let body_start = if lang_end < after_fence.len() {
            lang_end + 1
        } else {
            lang_end
        };
        let body_region = &after_fence[body_start..];
        if let Some(close) = body_region.find("```") {
            let body = body_region[..close].trim();
            let publish_only = (lang.is_empty() || lang == "bash" || lang == "sh")
                && body.lines().all(|l| {
                    let l = l.trim();
                    l.is_empty()
                        || l.starts_with("buzz messages send")
                        || l.starts_with("buzz reactions add")
                });
            if !publish_only {
                cleaned.push_str(&rest[start..start + 3 + body_start + close + 3]);
            }
            rest = &body_region[close + 3..];
        } else {
            cleaned.push_str(&rest[start..]);
            rest = "";
            break;
        }
    }
    cleaned.push_str(rest);

    // Remove standalone publish lines.
    cleaned
        .lines()
        .filter(|line| {
            let t = line.trim();
            !t.starts_with("buzz messages send") && !t.starts_with("buzz reactions add")
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovers_kimi_embedded_buzz_cli() {
        let text = r#"Ready.<|tool_calls_section_begin|><|tool_call_begin|>functions.buzz-cli:1<|tool_call_argument_begin|>{"command": "messages send --channel c --content hi"}<|tool_call_end|><|tool_calls_section_end|>"#;
        let cmds = extract_publish_commands(text);
        assert_eq!(cmds.len(), 1);
        assert_eq!(cmds[0], "buzz messages send --channel c --content hi");
    }

    #[test]
    fn recovers_kimi_execute_bash() {
        let text = r#"Sending now.<|tool_calls_section_begin|><|tool_call_begin|>functions.execute_bash:1<|tool_call_argument_begin|>{"command": "buzz messages send --channel c --content hi"}<|tool_call_end|><|tool_calls_section_end|>"#;
        let cmds = extract_publish_commands(text);
        assert_eq!(cmds.len(), 1);
        assert!(cmds[0].starts_with("buzz messages send"));
    }

    #[test]
    fn recovers_plain_buzz_send_line() {
        let text = "buzz messages send --channel c --content hello";
        let cmds = extract_publish_commands(text);
        assert_eq!(cmds, vec!["buzz messages send --channel c --content hello"]);
    }

    #[test]
    fn recovers_kimi_structured_messages_send() {
        let text = r#"Hi.<|tool_calls_section_begin|><|tool_call_begin|>functions.buzz-agent___buzz_messages_send:1<|tool_call_argument_begin|>{"channel": "c", "content": "hello", "reply_to": "evt"}<|tool_call_end|><|tool_calls_section_end|>"#;
        let cmds = extract_publish_commands(text);
        assert_eq!(cmds.len(), 1);
        assert!(cmds[0].contains("buzz messages send --channel c"));
        assert!(cmds[0].contains("--reply-to evt"));
        assert!(cmds[0].contains("hello"));
    }

    #[test]
    fn shell_alias_matches_buzz_messages_send() {
        assert!(looks_like_shell_alias(
            "functions.buzz-agent___buzz_messages_send"
        ));
    }

    #[test]
    fn recovers_kimi_message_marker_with_reply_to() {
        let text = r#"<|tool_calls_section_begin|><|tool_call_begin|>functions.buzz:1<|message|>{"channel": "28c8bf26-10fa-42e7-b658-38092562bfe1", "reply_to": "74af83254ab76acc923dff340cfc39a5e869a34493403c8954f96381d462648d", "content": "Received loud and clear!"}<|tool_call_end|><|tool_calls_section_end|>"#;
        let cmds = extract_publish_commands(text);
        assert_eq!(cmds.len(), 1);
        assert!(cmds[0].contains("buzz messages send --channel 28c8bf26"));
        assert!(cmds[0].contains("--reply-to 74af83254"));
        assert!(cmds[0].contains("Received loud and clear"));
    }

    #[test]
    fn empty_shell_call_has_no_command() {
        let shell = "buzz-dev-mcp__shell";
        let call = ToolCall {
            provider_id: "shell-0".into(),
            name: shell.into(),
            arguments: json!({}),
            provider_extra: Map::new(),
        };
        assert!(is_empty_shell_call(&call, shell));
    }
}
