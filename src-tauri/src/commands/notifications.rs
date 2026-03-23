use crate::models::notice::Notice;
use crate::server::websocket::BrowserHub;
use crate::state::AppState;
use serde::Serialize;
use std::sync::Arc;
use tauri::Emitter;
use tokio::sync::RwLock;

#[derive(Serialize)]
pub struct ServerStatus {
    pub running: bool,
    pub port: u16,
    pub items: usize,
}

#[tauri::command]
pub async fn get_notices(state: tauri::State<'_, Arc<RwLock<AppState>>>) -> Result<Vec<Notice>, String> {
    let s = state.read().await;
    Ok(s.notices.clone())
}

#[tauri::command]
pub async fn clear_notices(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
) -> Result<(), String> {
    {
        let mut s = state.write().await;
        s.notices.clear();
    }
    hub.broadcast("{\"type\":\"clear\"}");
    Ok(())
}

#[tauri::command]
pub async fn get_server_status(state: tauri::State<'_, Arc<RwLock<AppState>>>) -> Result<ServerStatus, String> {
    let s = state.read().await;
    Ok(ServerStatus {
        running: s.server_running,
        port: s.port,
        items: s.notices.len(),
    })
}

#[tauri::command]
pub async fn send_notice(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    hub: tauri::State<'_, BrowserHub>,
    app_handle: tauri::AppHandle,
    body: String,
    session_id: Option<String>,
) -> Result<Notice, String> {
    use crate::models::notice::NoticeSocketMessage;

    let notice = Notice::make(
        Some("Agent Monitor"),
        Some(&body),
        Some("agm"),
        session_id.as_deref(),
        None,
        Some(&body),
        None,
    );

    {
        let mut s = state.write().await;
        s.notices.insert(0, notice.clone());
        while s.notices.len() > s.max_items {
            s.notices.pop();
        }
    }

    // Broadcast over WebSocket
    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        hub.broadcast(&json);
    }

    // Emit Tauri event for frontend
    let _ = app_handle.emit("notice:new", &notice);

    Ok(notice)
}
