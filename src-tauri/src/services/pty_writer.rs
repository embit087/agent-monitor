use std::time::Duration;
use tokio::process::Command;

/// Build the AppleScript to type text and submit, varying by source kind.
///
/// - `claudeCode` / `terminal`: plain Return key (Enter sends in terminal)
/// - `cursor`: paste from clipboard + Cmd+Enter via key code
///   (Cursor is Electron — `keystroke` can misfire; clipboard paste + raw
///    key code is more reliable)
fn build_keystroke_script(text: &str, source_kind: &str) -> String {
    match source_kind {
        "cursor" | "claudeCode" => {
            // Clipboard paste then Cmd+Enter via key code 36
            // Cursor is Electron, Claude Code is terminal — both benefit from
            // clipboard paste (reliable for long/special text) + Cmd+Enter.
            let escaped = text.replace('\\', "\\\\").replace('"', "\\\"");
            format!(
                r#"set the clipboard to "{escaped}"
tell application "System Events"
    keystroke "v" using command down
    delay 0.15
    key code 36 using command down
end tell"#
            )
        }
        _ => {
            // For plain terminal sessions: keystroke + Enter
            let escaped = text.replace('\\', "\\\\").replace('"', "\\\"");
            format!(
                r#"tell application "System Events"
    keystroke "{escaped}"
    keystroke return
end tell"#
            )
        }
    }
}

/// Send text to the focused window by typing keystrokes via AppleScript.
async fn send_keystrokes(text: &str, source_kind: &str) -> Result<(), String> {
    let script = build_keystroke_script(text, source_kind);

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            if output.status.success() {
                Ok(())
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                Err(format!("keystroke failed: {stderr}"))
            }
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("keystroke timed out (5s)".to_string()),
    }
}

/// Focus the session window via winid, wait briefly, then type the text.
/// Uses the appropriate submit key based on `source_kind`:
/// - "cursor" → Cmd+Enter
/// - "claudeCode" / "terminal" / other → Enter
pub async fn send_to_session(
    session_id: &str,
    text: &str,
    winid_path: Option<&std::path::Path>,
    source_kind: &str,
) -> Result<(), String> {
    // Focus the target window first
    crate::services::winid_runner::open_session(session_id, winid_path).await?;

    // Brief pause for window to come to front
    tokio::time::sleep(Duration::from_millis(150)).await;

    // Type the text with source-appropriate submit key
    send_keystrokes(text, source_kind).await?;

    // Brief pause then refocus Agent Monitor via System Events
    tokio::time::sleep(Duration::from_millis(100)).await;
    focus_self().await;

    Ok(())
}

/// Bring Agent Monitor back to front via System Events.
async fn focus_self() {
    let script = r#"
tell application "System Events"
    tell process "agent-monitor"
        set frontmost to true
    end tell
end tell
"#;
    let _ = tokio::time::timeout(Duration::from_secs(3), async {
        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .await
    })
    .await;
}
