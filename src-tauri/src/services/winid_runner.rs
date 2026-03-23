use std::path::Path;
use std::time::Duration;
use tokio::process::Command;

pub async fn open_session(session_id: &str, winid_path: Option<&Path>) -> Result<(), String> {
    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let cmd_str = format!("{} open {}", shell_quote(&winid), shell_quote(session_id));

    // First attempt
    match run_winid_command(&cmd_str).await {
        Ok(()) => return Ok(()),
        Err(_) => {
            // Retry after 500ms
            tokio::time::sleep(Duration::from_millis(500)).await;
            run_winid_command(&cmd_str).await
        }
    }
}

pub async fn remove_session(session_id: &str, winid_path: Option<&Path>) -> Result<(), String> {
    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let cmd_str = format!("{} remove {}", shell_quote(&winid), shell_quote(session_id));
    run_winid_command(&cmd_str).await
}

pub async fn init_new_terminal(
    winid_path: Option<&Path>,
    chain_command: Option<&str>,
) -> Result<String, String> {
    let session_id = format!("manual-{}", &uuid::Uuid::new_v4().to_string()[..8]);

    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let mut terminal_cmd = format!("{} save {}", shell_quote(&winid), shell_quote(&session_id));
    if let Some(chain) = chain_command {
        terminal_cmd = format!("{terminal_cmd} && {chain}");
    }

    // AppleScript to open new Terminal window
    let script = format!(
        r#"tell application "Terminal"
    activate
    do script "{}"
end tell"#,
        terminal_cmd.replace('\\', "\\\\").replace('"', "\\\"")
    );

    let result = tokio::time::timeout(Duration::from_secs(8), async {
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
                Ok(session_id)
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                Err(format!("AppleScript failed: {stderr}"))
            }
        }
        Ok(Err(e)) => Err(format!("Failed to run osascript: {e}")),
        Err(_) => Err("Timed out opening terminal".to_string()),
    }
}

async fn run_winid_command(cmd: &str) -> Result<(), String> {
    let result = tokio::time::timeout(Duration::from_secs(8), async {
        Command::new("/bin/bash")
            .arg("-lc")
            .arg(cmd)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                if stdout.contains("Warning:") {
                    Err(format!("winid warning: {stdout}"))
                } else {
                    Ok(())
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                Err(format!("winid failed: {stderr}"))
            }
        }
        Ok(Err(e)) => Err(format!("Failed to execute: {e}")),
        Err(_) => Err("winid command timed out (8s)".to_string()),
    }
}

/// Run `winid save <id>` to capture the frontmost window.
pub async fn save_session(session_id: &str, winid_path: Option<&Path>) -> Result<(), String> {
    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let cmd_str = format!("{} save {}", shell_quote(&winid), shell_quote(session_id));
    run_winid_command(&cmd_str).await
}

/// Read the app_name from winid metadata to detect the source kind.
pub fn detect_source(session_id: &str) -> String {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return "other".to_string(),
    };
    let path = home.join(".winids").join(session_id);
    let contents = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return "other".to_string(),
    };
    let win_name = contents
        .lines()
        .find_map(|l| l.strip_prefix("win_name="))
        .unwrap_or("")
        .to_lowercase();

    if win_name.contains("cursor") {
        "Cursor".to_string()
    } else if win_name.contains("claude") {
        "Claude Code".to_string()
    } else {
        "Terminal".to_string()
    }
}

fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
