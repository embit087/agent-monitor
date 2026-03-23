use serde::Serialize;
use std::collections::HashSet;
use std::time::Duration;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveredSession {
    pub app: String,
    pub title: String,
    pub tty: Option<String>,
    pub pid: Option<u32>,
    pub source_kind: String,
    pub already_added: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrphanedSession {
    pub key: String,
    pub title: String,
    pub source_kind: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoverResult {
    pub sessions: Vec<DiscoveredSession>,
    pub orphaned: Vec<OrphanedSession>,
}

/// Scan Terminal.app tabs for agent sessions (Claude Code, Cursor Agent, etc.)
async fn discover_terminal_tabs() -> Vec<DiscoveredSession> {
    let script = r#"
tell application "System Events"
    if not (exists process "Terminal") then return ""
end tell
tell application "Terminal"
    set output to ""
    repeat with w in windows
        set winName to name of w as string
        set tabCount to count of tabs of w
        repeat with i from 1 to tabCount
            set t to tab i of w
            try
                set tabTty to tty of t as string
                set output to output & tabTty & "	" & winName & linefeed
            end try
        end repeat
    end repeat
    return output
end tell
"#;

    let result = tokio::time::timeout(Duration::from_secs(8), async {
        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .await
    })
    .await;

    let stdout = match result {
        Ok(Ok(output)) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).to_string()
        }
        _ => return vec![],
    };

    let mut sessions = Vec::new();
    let mut seen_ttys = HashSet::new();

    for line in stdout.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let (tty, title) = match line.split_once('\t') {
            Some(pair) => pair,
            None => continue,
        };

        // Dedup by TTY
        if !seen_ttys.insert(tty.to_string()) {
            continue;
        }

        let lower = title.to_lowercase();
        let source_kind = if lower.contains("cursor-agent") {
            "cursor"
        } else if lower.contains("claude") {
            "claudeCode"
        } else {
            continue;
        };

        sessions.push(DiscoveredSession {
            app: "Terminal".to_string(),
            title: title.to_string(),
            tty: Some(tty.to_string()),
            pid: None, // filled in below
            source_kind: source_kind.to_string(),
            already_added: false,
        });
    }

    // Batch-lookup PIDs for discovered TTYs.
    let tty_pid_map = lookup_pids_by_tty().await;
    for s in &mut sessions {
        if let Some(ref tty) = s.tty {
            // Strip "/dev/" prefix to match ps output (e.g. "ttys003")
            let short = tty.strip_prefix("/dev/").unwrap_or(tty);
            if let Some(&pid) = tty_pid_map.get(short) {
                s.pid = Some(pid);
            }
        }
    }

    sessions
}

/// Map TTY short names (e.g. "ttys003") to the PID of the session leader.
/// Uses `ps -eo tty=,pid=,ppid=` and picks the process whose ppid is 1 or
/// the lowest PID on each TTY (the login shell / session leader).
async fn lookup_pids_by_tty() -> std::collections::HashMap<String, u32> {
    use std::collections::HashMap;

    let result = tokio::time::timeout(Duration::from_secs(3), async {
        Command::new("ps")
            .args(["-eo", "tty=,pid=,ppid="])
            .output()
            .await
    })
    .await;

    let stdout = match result {
        Ok(Ok(output)) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).to_string()
        }
        _ => return HashMap::new(),
    };

    // For each TTY, keep the lowest PID (session leader / login shell).
    let mut map: HashMap<String, u32> = HashMap::new();
    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 2 {
            continue;
        }
        let tty = parts[0].trim();
        if tty == "??" || tty == "-" || tty.is_empty() {
            continue;
        }
        if let Ok(pid) = parts[1].parse::<u32>() {
            map.entry(tty.to_string())
                .and_modify(|existing| {
                    if pid < *existing {
                        *existing = pid;
                    }
                })
                .or_insert(pid);
        }
    }
    map
}

/// Scan for Cursor windows via System Events.
async fn discover_cursor_windows() -> Vec<DiscoveredSession> {
    let script = r#"
tell application "System Events"
    set output to ""
    repeat with procName in {"Cursor", "agent", "stable"}
        try
            if exists process procName then
                tell process (procName as string)
                    repeat with w in windows
                        try
                            set winTitle to name of w as string
                            if winTitle is not "" then
                                set output to output & winTitle & linefeed
                            end if
                        end try
                    end repeat
                end tell
            end if
        end try
    end repeat
    return output
end tell
"#;

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .await
    })
    .await;

    let stdout = match result {
        Ok(Ok(output)) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).to_string()
        }
        _ => return vec![],
    };

    let mut sessions = Vec::new();
    let mut seen_titles = HashSet::new();

    for line in stdout.lines() {
        let title = line.trim();
        if title.is_empty() {
            continue;
        }
        if !seen_titles.insert(title.to_string()) {
            continue;
        }

        sessions.push(DiscoveredSession {
            app: "Cursor".to_string(),
            title: title.to_string(),
            tty: None,
            pid: None,
            source_kind: "cursor".to_string(),
            already_added: false,
        });
    }
    sessions
}

/// Collect TTYs and titles from winid files that are currently active in Agent Monitor.
fn active_ttys_and_titles(active_keys: &[String]) -> (HashSet<String>, HashSet<String>) {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return (HashSet::new(), HashSet::new()),
    };
    let store_dir = home.join(".winids");
    let mut ttys = HashSet::new();
    let mut titles = HashSet::new();

    for key in active_keys {
        let path = store_dir.join(key);
        if let Ok(contents) = std::fs::read_to_string(&path) {
            for line in contents.lines() {
                if let Some(tty) = line.strip_prefix("tty=") {
                    let tty = tty.trim();
                    if !tty.is_empty() {
                        ttys.insert(tty.to_string());
                    }
                }
                if let Some(title) = line.strip_prefix("win_name=") {
                    let title = title.trim();
                    if !title.is_empty() {
                        titles.insert(title.to_string());
                    }
                }
            }
        }
    }
    (ttys, titles)
}

/// Scan Ghostty windows for agent sessions via System Events.
async fn discover_ghostty_windows() -> Vec<DiscoveredSession> {
    let script = r#"
tell application "System Events"
    if not (exists process "ghostty") then return ""
    set output to ""
    tell process "ghostty"
        repeat with w in windows
            try
                set winTitle to name of w as string
                if winTitle is not "" then
                    set output to output & winTitle & linefeed
                end if
            end try
        end repeat
    end tell
    return output
end tell
"#;

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .await
    })
    .await;

    let stdout = match result {
        Ok(Ok(output)) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).to_string()
        }
        _ => return vec![],
    };

    let mut sessions = Vec::new();
    let mut seen_titles = HashSet::new();

    for line in stdout.lines() {
        let title = line.trim();
        if title.is_empty() {
            continue;
        }
        if !seen_titles.insert(title.to_string()) {
            continue;
        }

        let lower = title.to_lowercase();
        let source_kind = if lower.contains("claude") {
            "claudeCode"
        } else if lower.contains("cursor-agent") || lower.contains("cursor agent") {
            "cursor"
        } else {
            // Include plain Ghostty windows too so they can be tracked
            "terminal"
        };

        // Only include windows that look like agent sessions
        if source_kind == "terminal" && !lower.contains("agent") {
            // Still include — user may want to track any Ghostty window
        }

        sessions.push(DiscoveredSession {
            app: "ghostty".to_string(),
            title: title.to_string(),
            tty: None,
            pid: None,
            source_kind: source_kind.to_string(),
            already_added: false,
        });
    }
    sessions
}

/// Discover all running agent sessions, marking ones already tracked.
/// Also detects orphaned sessions (active tabs with no matching open terminal).
/// `active_keys` are the session keys currently in Agent Monitor's notices.
pub async fn discover_all(active_keys: &[String]) -> DiscoverResult {
    let (terminal, cursor, ghostty) =
        tokio::join!(discover_terminal_tabs(), discover_cursor_windows(), discover_ghostty_windows());

    let (registered_ttys, registered_titles) = active_ttys_and_titles(active_keys);

    // Collect all live TTYs and titles from discovered windows
    let mut live_ttys = HashSet::new();
    let mut live_titles = HashSet::new();
    for s in &terminal {
        if let Some(ref tty) = s.tty {
            live_ttys.insert(tty.clone());
        }
        live_titles.insert(s.title.clone());
    }
    for s in &cursor {
        live_titles.insert(s.title.clone());
    }
    for s in &ghostty {
        live_titles.insert(s.title.clone());
    }

    let mut all = Vec::new();

    for mut s in terminal {
        if let Some(ref tty) = s.tty {
            if registered_ttys.contains(tty) {
                s.already_added = true;
            }
        }
        all.push(s);
    }

    for mut s in cursor {
        if registered_titles.contains(&s.title) {
            s.already_added = true;
        }
        all.push(s);
    }

    for mut s in ghostty {
        if registered_titles.contains(&s.title) {
            s.already_added = true;
        }
        all.push(s);
    }

    // Detect orphaned sessions: active keys whose terminal is no longer open
    let orphaned = find_orphaned(active_keys, &live_ttys, &live_titles);

    DiscoverResult { sessions: all, orphaned }
}

/// Check each active session key against live TTYs/titles.
/// Returns keys that have no matching open terminal window.
fn find_orphaned(
    active_keys: &[String],
    live_ttys: &HashSet<String>,
    live_titles: &HashSet<String>,
) -> Vec<OrphanedSession> {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return vec![],
    };
    let store_dir = home.join(".winids");
    let mut orphaned = Vec::new();

    for key in active_keys {
        let meta_path = store_dir.join(key);

        // No metadata file at all → orphaned
        let contents = match std::fs::read_to_string(&meta_path) {
            Ok(c) => c,
            Err(_) => {
                orphaned.push(OrphanedSession {
                    key: key.clone(),
                    title: key.clone(),
                    source_kind: "unknown".to_string(),
                });
                continue;
            }
        };

        let mut tty: Option<String> = None;
        let mut win_name = String::new();
        let mut app_name = String::new();
        for line in contents.lines() {
            if let Some(v) = line.strip_prefix("tty=") {
                let v = v.trim();
                if !v.is_empty() {
                    tty = Some(v.to_string());
                }
            }
            if let Some(v) = line.strip_prefix("win_name=") {
                win_name = v.trim().to_string();
            }
            if let Some(v) = line.strip_prefix("app_name=") {
                app_name = v.trim().to_string();
            }
        }

        // Check if this session has a matching live terminal
        let is_live = if let Some(ref tty_val) = tty {
            // TTY-based match (Terminal.app sessions)
            live_ttys.contains(tty_val)
        } else if !win_name.is_empty() {
            // Title-based match (Cursor/Ghostty) — check if any live title contains the win_name
            live_titles.iter().any(|t| t.contains(&win_name) || win_name.contains(t.as_str()))
        } else {
            // No TTY or title to match — can't verify, assume live
            true
        };

        if !is_live {
            let source_kind = {
                let lower_win = win_name.to_lowercase();
                let lower_app = app_name.to_lowercase();
                if lower_win.contains("cursor") {
                    "cursor"
                } else if lower_win.contains("claude") {
                    "claudeCode"
                } else if lower_app.contains("ghostty") {
                    "terminal"
                } else {
                    "terminal"
                }
            };
            let display = if !win_name.is_empty() {
                win_name.clone()
            } else {
                key.clone()
            };
            orphaned.push(OrphanedSession {
                key: key.clone(),
                title: display,
                source_kind: source_kind.to_string(),
            });
        }
    }

    orphaned
}
