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
    pub source_kind: String,
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
        let source_kind = if lower.contains("cursor") {
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
            source_kind: source_kind.to_string(),
        });
    }
    sessions
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
            source_kind: "cursor".to_string(),
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

/// Discover all running agent sessions, excluding ones already tracked.
/// `active_keys` are the session keys currently in Agent Monitor's notices.
pub async fn discover_all(active_keys: &[String]) -> Vec<DiscoveredSession> {
    let (terminal, cursor) =
        tokio::join!(discover_terminal_tabs(), discover_cursor_windows());

    let (registered_ttys, registered_titles) = active_ttys_and_titles(active_keys);

    let mut all = Vec::new();

    for s in terminal {
        if let Some(ref tty) = s.tty {
            if registered_ttys.contains(tty) {
                continue;
            }
        }
        all.push(s);
    }

    for s in cursor {
        if registered_titles.contains(&s.title) {
            continue;
        }
        all.push(s);
    }

    all
}
