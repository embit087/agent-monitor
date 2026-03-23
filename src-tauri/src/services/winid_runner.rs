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
    // Read metadata before winid removes the file so we can close the actual window.
    let meta = read_session_meta(session_id);

    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let cmd_str = format!("{} remove {}", shell_quote(&winid), shell_quote(session_id));
    let _ = run_winid_command(&cmd_str).await;

    // Best-effort: close the actual terminal tab / window.
    if let Some(m) = meta {
        let _ = close_actual_window(&m).await;
    }

    Ok(())
}

struct SessionMeta {
    app_name: String,
    win_name: String,
    tty: Option<String>,
    pid: Option<u32>,
}

fn read_session_meta(session_id: &str) -> Option<SessionMeta> {
    let home = dirs::home_dir()?;
    let contents = std::fs::read_to_string(home.join(".winids").join(session_id)).ok()?;

    let mut app_name = String::new();
    let mut win_name = String::new();
    let mut tty: Option<String> = None;
    let mut pid: Option<u32> = None;

    for line in contents.lines() {
        if let Some(v) = line.strip_prefix("app_name=") { app_name = v.trim().to_string(); }
        if let Some(v) = line.strip_prefix("win_name=") { win_name = v.trim().to_string(); }
        if let Some(v) = line.strip_prefix("tty=") {
            let v = v.trim();
            if !v.is_empty() { tty = Some(v.to_string()); }
        }
        if let Some(v) = line.strip_prefix("pid=") {
            pid = v.trim().parse().ok();
        }
    }

    Some(SessionMeta { app_name, win_name, tty, pid })
}

/// Close the actual terminal/window for a session.
///
/// Strategy (layered escalation):
/// 1. Look up **live** PIDs on the TTY right now (stored PID may be stale)
/// 2. SIGTERM all processes on the TTY
/// 3. Wait, verify TTY is gone, escalate to SIGKILL if not
/// 4. Close the terminal tab/window via AppleScript with `saving no`
async fn close_actual_window(meta: &SessionMeta) -> Result<(), String> {
    let app = meta.app_name.to_lowercase();

    if app.contains("terminal") || app.contains("ghostty") {
        // ── Step 1: Kill all processes on the TTY ──
        if let Some(ref tty) = meta.tty {
            let short = tty.strip_prefix("/dev/").unwrap_or(tty);

            // Get current live PIDs on this TTY (not stale stored PID)
            let live_pids = pids_on_tty(short).await;

            // SIGTERM each process (try process group first)
            for pid in &live_pids {
                let _ = signal_pgid(*pid, "TERM").await;
            }
            // Also pkill as belt-and-suspenders
            let _ = Command::new("pkill")
                .args(["-TERM", "-t", short])
                .output()
                .await;

            // Brief wait for processes to exit
            tokio::time::sleep(Duration::from_millis(500)).await;

            // ── Step 2: Verify & escalate ──
            if std::path::Path::new(tty).exists() {
                // TTY still alive — escalate to SIGKILL
                let live_pids = pids_on_tty(short).await;
                for pid in &live_pids {
                    let _ = signal_pgid(*pid, "KILL").await;
                }
                let _ = Command::new("pkill")
                    .args(["-KILL", "-t", short])
                    .output()
                    .await;
                tokio::time::sleep(Duration::from_millis(300)).await;
            }
        } else if let Some(pid) = meta.pid {
            // No TTY (shouldn't happen for Terminal/Ghostty, but just in case)
            let _ = signal_pgid(pid, "TERM").await;
            tokio::time::sleep(Duration::from_millis(500)).await;
            if pid_exists(pid) {
                let _ = signal_pgid(pid, "KILL").await;
                tokio::time::sleep(Duration::from_millis(300)).await;
            }
        }

        // ── Step 3: Close the tab/window in the terminal app ──
        if app.contains("terminal") {
            if let Some(ref tty) = meta.tty {
                let escaped_tty = tty.replace('\\', "\\\\").replace('"', "\\\"");
                let script = format!(
                    r#"tell application "Terminal"
    repeat with w in windows
        set tabCount to count of tabs of w
        repeat with i from 1 to tabCount
            try
                if tty of tab i of w as string is "{escaped_tty}" then
                    close tab i of w saving no
                    return "closed"
                end if
            end try
        end repeat
    end repeat
end tell"#
                );
                let _ = run_osascript(&script).await;
            }
        } else {
            // Ghostty: close via System Events
            let title_prefix = if meta.win_name.len() > 30 {
                &meta.win_name[..30]
            } else {
                &meta.win_name
            };
            let escaped = title_prefix.replace('\\', "\\\\").replace('"', "\\\"");
            let script = format!(
                r#"tell application "System Events"
    try
        tell process "ghostty"
            repeat with w in windows
                if name of w contains "{escaped}" then
                    click button 1 of w
                    return "closed"
                end if
            end repeat
        end tell
    end try
end tell"#
            );
            let _ = run_osascript(&script).await;
        }

        Ok(())
    } else if app.contains("cursor") {
        let prefix = if meta.win_name.len() > 30 {
            &meta.win_name[..30]
        } else {
            &meta.win_name
        };
        let escaped = prefix.replace('\\', "\\\\").replace('"', "\\\"");
        let script = format!(
            r#"tell application "System Events"
    try
        tell process "Cursor"
            repeat with w in windows
                if name of w starts with "{escaped}" then
                    click button 1 of w
                    return "closed"
                end if
            end repeat
        end tell
    end try
end tell"#
        );
        run_osascript(&script).await
    } else {
        Err(format!("unknown app: {}", meta.app_name))
    }
}

/// Get live PIDs currently running on a TTY (e.g. "ttys003").
async fn pids_on_tty(tty_short: &str) -> Vec<u32> {
    let result = Command::new("ps")
        .args(["-t", tty_short, "-o", "pid="])
        .output()
        .await;

    match result {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout)
                .lines()
                .filter_map(|l| l.trim().parse::<u32>().ok())
                .collect()
        }
        _ => vec![],
    }
}

/// Send a signal to a process group, falling back to single-process kill.
async fn signal_pgid(pid: u32, signal: &str) -> Result<(), String> {
    // kill -<signal> -<pid> targets the process group
    let result = Command::new("kill")
        .arg(format!("-{signal}"))
        .arg(format!("-{pid}"))
        .output()
        .await;
    match result {
        Ok(output) if output.status.success() => Ok(()),
        _ => {
            // Fallback: kill just the single process
            let result = Command::new("kill")
                .arg(format!("-{signal}"))
                .arg(pid.to_string())
                .output()
                .await;
            match result {
                Ok(o) if o.status.success() => Ok(()),
                Ok(o) => Err(String::from_utf8_lossy(&o.stderr).to_string()),
                Err(e) => Err(e.to_string()),
            }
        }
    }
}

/// Check if a process is still alive.
fn pid_exists(pid: u32) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

async fn run_osascript(script: &str) -> Result<(), String> {
    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) if output.status.success() => Ok(()),
        Ok(Ok(output)) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(format!("osascript failed: {stderr}"))
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("osascript timed out".to_string()),
    }
}

pub async fn init_new_terminal(
    winid_path: Option<&Path>,
    chain_command: Option<&str>,
    bounds: Option<(i32, i32, u32, u32)>,
    terminal_app: Option<&str>,
    cwd: Option<&str>,
) -> Result<String, String> {
    let app = terminal_app.unwrap_or("terminal");
    if app == "ghostty" {
        return init_new_ghostty(winid_path, chain_command, bounds, cwd).await;
    }

    let session_id = format!("manual-{}", &uuid::Uuid::new_v4().to_string()[..8]);

    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let mut terminal_cmd = String::new();
    if let Some(dir) = cwd {
        if !dir.is_empty() {
            terminal_cmd = format!("cd {} && ", shell_quote(dir));
        }
    }
    terminal_cmd = format!("{terminal_cmd}{} save {}", shell_quote(&winid), shell_quote(&session_id));
    if let Some(chain) = chain_command {
        terminal_cmd = format!("{terminal_cmd} && {chain}");
    }

    // AppleScript to open new Terminal window, optionally with position/size
    let bounds_script = if let Some((x, y, w, h)) = bounds {
        format!(
            r#"
    set bounds of front window to {{{x}, {y}, {}, {}}}
"#,
            x as i64 + w as i64,
            y as i64 + h as i64
        )
    } else {
        String::new()
    };

    let script = format!(
        r#"tell application "Terminal"
    activate
    do script "{}"{}
end tell"#,
        terminal_cmd.replace('\\', "\\\\").replace('"', "\\\""),
        bounds_script
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

/// Launch a new Ghostty terminal window with hidden title bar.
/// Ghostty doesn't support `do script` AppleScript, so we:
/// 1. Activate Ghostty (opens a new window if not running, otherwise Cmd+N)
/// 2. Type the command via System Events keystrokes
async fn init_new_ghostty(
    winid_path: Option<&Path>,
    chain_command: Option<&str>,
    bounds: Option<(i32, i32, u32, u32)>,
    cwd: Option<&str>,
) -> Result<String, String> {
    let session_id = format!("manual-{}", &uuid::Uuid::new_v4().to_string()[..8]);

    let winid = winid_path
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "winid".to_string());

    let mut terminal_cmd = String::new();
    if let Some(dir) = cwd {
        if !dir.is_empty() {
            terminal_cmd = format!("cd {} && ", shell_quote(dir));
        }
    }
    terminal_cmd = format!("{terminal_cmd}{} save {}", shell_quote(&winid), shell_quote(&session_id));
    if let Some(chain) = chain_command {
        terminal_cmd = format!("{terminal_cmd} && {chain}");
    }

    let escaped_cmd = terminal_cmd.replace('\\', "\\\\").replace('"', "\\\"");

    // Position script using System Events (Ghostty doesn't support `bounds` via its own scripting)
    let bounds_script = if let Some((x, y, w, h)) = bounds {
        format!(
            r#"
    tell application "System Events"
        tell process "ghostty"
            try
                set position of front window to {{{x}, {y}}}
                set size of front window to {{{w}, {h}}}
            end try
        end tell
    end tell"#
        )
    } else {
        String::new()
    };

    let script = format!(
        r#"
set ghosttyWasRunning to false
tell application "System Events"
    if exists process "ghostty" then
        set ghosttyWasRunning to true
    end if
end tell

tell application "ghostty" to activate
delay 0.3

if ghosttyWasRunning then
    tell application "System Events"
        tell process "ghostty"
            keystroke "n" using command down
        end tell
    end tell
    delay 0.5
end if

delay 0.3
{bounds_script}

tell application "System Events"
    tell process "ghostty"
        keystroke "{escaped_cmd}"
        keystroke return
    end tell
end tell
"#
    );

    let result = tokio::time::timeout(Duration::from_secs(12), async {
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
                Err(format!("Ghostty AppleScript failed: {stderr}"))
            }
        }
        Ok(Err(e)) => Err(format!("Failed to run osascript: {e}")),
        Err(_) => Err("Timed out opening Ghostty terminal".to_string()),
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
    let app_name = contents
        .lines()
        .find_map(|l| l.strip_prefix("app_name="))
        .unwrap_or("")
        .to_lowercase();
    let win_name = contents
        .lines()
        .find_map(|l| l.strip_prefix("win_name="))
        .unwrap_or("")
        .to_lowercase();

    if win_name.contains("cursor") {
        "Cursor".to_string()
    } else if win_name.contains("claude") {
        "Claude Code".to_string()
    } else if app_name.contains("ghostty") {
        "Ghostty".to_string()
    } else {
        "Terminal".to_string()
    }
}

fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
