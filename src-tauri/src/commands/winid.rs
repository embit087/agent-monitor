use crate::models::notice::{Notice, NoticeSocketMessage};
use crate::server::websocket::BrowserHub;
use crate::state::AppState;
use serde::Serialize;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::Emitter;
use tokio::sync::RwLock;

#[derive(Serialize)]
pub struct WinidResult {
    pub ok: bool,
    pub message: String,
}

#[derive(Serialize)]
pub struct PtyWriteResult {
    pub ok: bool,
    pub message: String,
    pub tty: Option<String>,
}

#[tauri::command]
pub async fn open_winid_session(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    session_id: String,
    app_handle: tauri::AppHandle,
) -> Result<WinidResult, String> {
    let id = session_id.trim().to_string();
    if id.is_empty() {
        return Ok(WinidResult { ok: false, message: "empty session id".to_string() });
    }

    // Per-session debounce
    {
        let mut s = state.write().await;
        let now = Instant::now();
        if let Some(last) = s.switch_times.get(&id) {
            if now.duration_since(*last) < Duration::from_secs(1) {
                return Ok(WinidResult { ok: false, message: "debounced".to_string() });
            }
        }
        s.switch_times.insert(id.clone(), now);

        // Cleanup old entries
        if s.switch_times.len() > 100 {
            let cutoff = now - Duration::from_secs(120);
            s.switch_times.retain(|_, v| *v > cutoff);
        }
    }

    let _ = app_handle.emit("winid:status", serde_json::json!({"status": "switching", "id": &id}));

    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };

    let result = crate::services::winid_runner::open_session(&id, winid_path.as_deref()).await;

    match result {
        Ok(()) => {
            let _ = app_handle.emit("winid:status", serde_json::json!({"status": "succeeded", "id": &id}));
            Ok(WinidResult { ok: true, message: format!("Switched to {id}") })
        }
        Err(msg) => {
            // Clear debounce on failure
            {
                let mut s = state.write().await;
                s.switch_times.remove(&id);
            }
            let _ = app_handle.emit("winid:status", serde_json::json!({"status": "failed", "id": &id, "error": &msg}));
            Ok(WinidResult { ok: false, message: msg })
        }
    }
}

#[tauri::command]
pub async fn close_winid_session(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
    session_id: String,
) -> Result<(), String> {
    let id = session_id.trim().to_string();
    if id.is_empty() {
        return Ok(());
    }

    {
        let mut s = state.write().await;
        s.notices.retain(|n| {
            n.action
                .as_ref()
                .map(|a| a.trim() != id)
                .unwrap_or(true)
        });
        s.switch_times.remove(&id);
    }

    hub.broadcast("{\"type\":\"clear\"}");

    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };
    let _ = crate::services::winid_runner::remove_session(&id, winid_path.as_deref()).await;

    Ok(())
}

#[tauri::command]
pub async fn init_new_terminal(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
    chain_command: Option<String>,
) -> Result<String, String> {
    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };

    let session_id = crate::services::winid_runner::init_new_terminal(
        winid_path.as_deref(),
        chain_command.as_deref(),
    )
    .await?;

    // Create a manual terminal notice
    let notice = Notice::make(
        Some("Terminal"),
        Some(&format!("Manual switch target for WINID {session_id}.")),
        Some("Manual"),
        Some(&session_id),
        None,
        None,
        None,
    );

    {
        let mut s = state.write().await;
        // Remove existing manual entry for same WINID
        s.notices.retain(|n| {
            !(n.title.to_lowercase().contains("terminal")
                && n.source.as_deref() == Some("Manual")
                && n.action.as_deref() == Some(&session_id))
        });
        s.notices.insert(0, notice.clone());
    }

    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        hub.broadcast(&json);
    }

    Ok(session_id)
}

#[tauri::command]
pub async fn upsert_manual_terminal(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
    winid: String,
) -> Result<(), String> {
    let winid = winid.trim().to_string();
    if winid.is_empty() {
        return Ok(());
    }

    let notice = Notice::make(
        Some("Terminal"),
        Some(&format!("Manual switch target for WINID {winid}.")),
        Some("Manual"),
        Some(&winid),
        None,
        None,
        None,
    );

    {
        let mut s = state.write().await;
        s.notices.retain(|n| {
            !(n.title.to_lowercase().contains("terminal")
                && n.source.as_deref().map(|s| s.eq_ignore_ascii_case("Manual")).unwrap_or(false)
                && n.action.as_deref() == Some(&winid))
        });
        s.notices.insert(0, notice.clone());
    }

    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        hub.broadcast(&json);
    }

    Ok(())
}

/// Capture the frontmost window as a new session.
/// User should bring the target window to front before calling this.
#[tauri::command]
pub async fn capture_frontmost_session(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
) -> Result<WinidResult, String> {
    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };

    let session_id = format!("capture-{}", &uuid::Uuid::new_v4().to_string()[..8]);

    // Run winid save to capture the frontmost window
    crate::services::winid_runner::save_session(&session_id, winid_path.as_deref()).await?;

    // Detect what kind of app it is from the saved metadata
    let title = crate::services::winid_runner::detect_source(&session_id);

    // Create a notice so it appears in the session list
    let notice = Notice::make(
        Some(&title),
        Some(&format!("Captured running session {session_id}")),
        Some("Capture"),
        Some(&session_id),
        None,
        None,
        None,
    );

    {
        let mut s = state.write().await;
        s.notices.insert(0, notice.clone());
    }

    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        hub.broadcast(&json);
    }

    let _ = state.read().await;
    Ok(WinidResult {
        ok: true,
        message: format!("Captured as {session_id} ({title})"),
    })
}

#[tauri::command]
pub async fn send_to_session(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    session_id: String,
    text: String,
    source_kind: Option<String>,
) -> Result<PtyWriteResult, String> {
    let id = session_id.trim().to_string();
    if id.is_empty() {
        return Ok(PtyWriteResult {
            ok: false,
            message: "empty session id".to_string(),
            tty: None,
        });
    }
    let text = text.trim_end_matches('\n').to_string();
    if text.is_empty() {
        return Ok(PtyWriteResult {
            ok: false,
            message: "empty text".to_string(),
            tty: None,
        });
    }

    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };

    let kind = source_kind.as_deref().unwrap_or("terminal");

    match crate::services::pty_writer::send_to_session(
        &id,
        &text,
        winid_path.as_deref(),
        kind,
    )
    .await
    {
        Ok(()) => Ok(PtyWriteResult {
            ok: true,
            message: format!("Typed into {id}"),
            tty: None,
        }),
        Err(e) => Ok(PtyWriteResult {
            ok: false,
            message: e,
            tty: None,
        }),
    }
}

/// Scan running Terminal.app and Cursor windows for agent sessions.
#[tauri::command]
pub async fn discover_sessions(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<Vec<crate::services::session_discover::DiscoveredSession>, String> {
    // Collect session keys currently tracked in Agent Monitor
    let active_keys: Vec<String> = {
        let s = state.read().await;
        let mut keys = std::collections::HashSet::new();
        for n in &s.notices {
            if let Some(action) = &n.action {
                let k = action.trim().to_string();
                if !k.is_empty() {
                    keys.insert(k);
                }
            }
        }
        keys.into_iter().collect()
    };

    Ok(crate::services::session_discover::discover_all(&active_keys).await)
}

/// Register a discovered session by saving its window via winid and creating a notice.
#[tauri::command]
pub async fn register_discovered_session(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
    app: String,
    title: String,
    tty: Option<String>,
    source_kind: String,
) -> Result<WinidResult, String> {
    let session_id = format!("disc-{}", &uuid::Uuid::new_v4().to_string()[..8]);

    // Write winid metadata manually (we already know the window info)
    let home = dirs::home_dir().ok_or("cannot find home dir")?;
    let store_dir = home.join(".winids");
    let _ = std::fs::create_dir_all(&store_dir);

    let mut meta = format!(
        "app_name={app}\nwin_name={title}\nsaved_at={}",
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S")
    );
    if let Some(ref tty_val) = tty {
        meta.push_str(&format!("\ntty={tty_val}"));
    }
    std::fs::write(store_dir.join(&session_id), &meta)
        .map_err(|e| format!("Failed to write winid metadata: {e}"))?;

    // Determine display title
    let display_title = match source_kind.as_str() {
        "cursor" => "Cursor",
        "claudeCode" => "Claude Code",
        _ => "Terminal",
    };

    let notice = Notice::make(
        Some(display_title),
        Some(&format!("Discovered: {title}")),
        Some("Discover"),
        Some(&session_id),
        None,
        None,
        None,
    );

    {
        let mut s = state.write().await;
        s.notices.insert(0, notice.clone());
    }

    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        hub.broadcast(&json);
    }

    Ok(WinidResult {
        ok: true,
        message: format!("Registered {display_title}: {session_id}"),
    })
}

/// Arrange agent windows using a named layout.
/// Reads winid metadata for each session to find app_name, win_name, tty.
#[tauri::command]
pub async fn arrange_windows(
    session_ids: Vec<String>,
    layout: String,
) -> Result<WinidResult, String> {
    use crate::services::window_layout;

    if session_ids.is_empty() {
        return Ok(WinidResult { ok: false, message: "no sessions".to_string() });
    }

    let screen = window_layout::get_screen_size().await?;
    let rects = window_layout::compute_layout(session_ids.len(), &layout, &screen);

    let home = dirs::home_dir().ok_or("cannot find home dir")?;
    let store_dir = home.join(".winids");
    let mut arranged = 0u32;
    let mut errors = Vec::new();

    for (i, sid) in session_ids.iter().enumerate() {
        let meta_path = store_dir.join(sid);
        let meta = match std::fs::read_to_string(&meta_path) {
            Ok(c) => c,
            Err(_) => { errors.push(format!("{sid}: no metadata")); continue; }
        };

        let mut app_name = String::new();
        let mut win_name = String::new();
        let mut tty = String::new();
        for line in meta.lines() {
            if let Some(v) = line.strip_prefix("app_name=") { app_name = v.trim().to_string(); }
            if let Some(v) = line.strip_prefix("win_name=") { win_name = v.trim().to_string(); }
            if let Some(v) = line.strip_prefix("tty=") { tty = v.trim().to_string(); }
        }

        let rect = &rects[i];
        let result = if !tty.is_empty() {
            window_layout::set_terminal_bounds_by_tty(&tty, rect).await
        } else if !app_name.is_empty() && !win_name.is_empty() {
            // Use a short prefix of the window name for matching
            let match_title = if win_name.len() > 30 {
                &win_name[..30]
            } else {
                &win_name
            };
            window_layout::set_window_bounds(&app_name, match_title, rect).await
        } else {
            Err(format!("{sid}: missing app_name/win_name/tty"))
        };

        match result {
            Ok(()) => arranged += 1,
            Err(e) => errors.push(e),
        }
    }

    let msg = if errors.is_empty() {
        format!("Arranged {arranged} windows ({layout})")
    } else {
        format!("Arranged {arranged}, {} errors", errors.len())
    };

    Ok(WinidResult { ok: arranged > 0, message: msg })
}

/// Remove sessions whose winid metadata or TTY device no longer exists.
/// Returns the number of sessions cleaned up.
#[tauri::command]
pub async fn cleanup_stale_sessions(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
) -> Result<WinidResult, String> {
    let home = dirs::home_dir().ok_or("cannot find home dir")?;
    let store_dir = home.join(".winids");

    // Collect unique session keys from notices
    let session_keys: Vec<String> = {
        let s = state.read().await;
        let mut keys = std::collections::HashSet::new();
        for n in &s.notices {
            if let Some(action) = &n.action {
                let k = action.trim().to_string();
                if !k.is_empty() {
                    keys.insert(k);
                }
            }
        }
        keys.into_iter().collect()
    };

    let mut stale: Vec<String> = Vec::new();

    for key in &session_keys {
        let meta_path = store_dir.join(key);

        // No winid metadata file → stale
        if !meta_path.exists() {
            stale.push(key.clone());
            continue;
        }

        // Read metadata and check TTY
        if let Ok(contents) = std::fs::read_to_string(&meta_path) {
            let tty = contents
                .lines()
                .find_map(|l| l.strip_prefix("tty="))
                .map(|v| v.trim().to_string());

            if let Some(tty_path) = tty {
                if !tty_path.is_empty() && !std::path::Path::new(&tty_path).exists() {
                    stale.push(key.clone());
                }
            }
        }
    }

    if stale.is_empty() {
        return Ok(WinidResult {
            ok: true,
            message: "All sessions are live".to_string(),
        });
    }

    let count = stale.len();

    // Remove notices for stale sessions and clean up winid files
    {
        let mut s = state.write().await;
        s.notices.retain(|n| {
            n.action
                .as_ref()
                .map(|a| !stale.contains(&a.trim().to_string()))
                .unwrap_or(true)
        });
        for key in &stale {
            s.switch_times.remove(key);
            let meta_path = store_dir.join(key);
            let _ = std::fs::remove_file(&meta_path);
        }
    }

    hub.broadcast("{\"type\":\"clear\"}");

    Ok(WinidResult {
        ok: true,
        message: format!("Removed {count} stale session{}", if count > 1 { "s" } else { "" }),
    })
}

const AGM_WINID: &str = "agm-self";

/// Save Agent Monitor's own window so we can switch back later via winid open.
#[tauri::command]
pub async fn save_self(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<(), String> {
    let winid_path = {
        let s = state.read().await;
        s.winid_path.clone()
    };
    crate::services::winid_runner::save_session(AGM_WINID, winid_path.as_deref()).await
}

/// Bring Agent Monitor window back to front via System Events.
/// Cannot use `tell application` or `winid open` because Tauri dev builds
/// aren't registered as a named macOS application.
#[tauri::command]
pub async fn focus_self() -> Result<(), String> {
    use tokio::process::Command;
    let script = r#"
tell application "System Events"
    tell process "agent-monitor"
        set frontmost to true
    end tell
end tell
"#;
    let result = tokio::time::timeout(Duration::from_secs(3), async {
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
            Err(format!("focus failed: {stderr}"))
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("focus timed out".to_string()),
    }
}
