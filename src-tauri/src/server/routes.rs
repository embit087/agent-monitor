use crate::models::notice::{
    encode_ready, NoticeSocketMessage, NotificationsEnvelope, NotifyPayload,
};
use crate::models::pad::{NotepadPayload, Pad, PadsEnvelope};
use crate::services::{cloud_sync, system_notify};
use crate::state::AppState;
use super::auth::auth_ok;
use super::websocket::BrowserHub;
use axum::{
    extract::{Query, State, WebSocketUpgrade},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Json},
    routing::{delete, get, post, put},
    Router,
};
use std::collections::HashMap;
use std::sync::Arc;
use tauri::Emitter;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct ServerState {
    pub app: Arc<RwLock<AppState>>,
    pub hub: BrowserHub,
    pub app_handle: tauri::AppHandle,
}

pub fn create_router(
    app_state: Arc<RwLock<AppState>>,
    hub: BrowserHub,
    app_handle: tauri::AppHandle,
) -> Router {
    let state = ServerState {
        app: app_state,
        hub,
        app_handle,
    };

    Router::new()
        .route("/api/health", get(health))
        .route("/api/notifications", get(get_notifications))
        .route("/api/notifications", delete(delete_notifications))
        .route("/api/notify", post(post_notify))
        .route("/api/ws", get(ws_upgrade))
        .route("/api/notepad", post(post_notepad))
        .route("/api/notepad", get(get_notepad))
        .route("/api/notepad", put(put_notepad))
        .route("/api/notepad", delete(delete_notepad))
        .with_state(state)
}

async fn health(State(state): State<ServerState>) -> impl IntoResponse {
    let s = state.app.read().await;
    let count = s.notices.len();
    Json(serde_json::json!({"ok": true, "items": count}))
}

async fn get_notifications(State(state): State<ServerState>) -> impl IntoResponse {
    let s = state.app.read().await;
    let envelope = NotificationsEnvelope {
        notifications: s.notices.clone(),
    };
    Json(serde_json::to_value(&envelope).unwrap_or_default())
}

async fn delete_notifications(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "unauthorized"})),
        );
    }
    {
        let mut s = state.app.write().await;
        s.notices.clear();
    }
    state.hub.broadcast("{\"type\":\"clear\"}");
    (StatusCode::OK, Json(serde_json::json!({"ok": true})))
}

async fn post_notify(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
    body: axum::body::Bytes,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "unauthorized"})),
        );
    }

    let payload: NotifyPayload = match serde_json::from_slice(&body) {
        Ok(p) => p,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "invalid json"})),
            );
        }
    };

    let silent = payload.silent;
    let tty = payload.tty.clone();
    let notice = payload.into_notice();

    // Reconcile: if the notice's action doesn't match a known session,
    // try to find a discovered/manual session with the same TTY.
    // The notification's session key (from the agent) takes priority:
    // rewrite all existing notices under the old discovered key to the
    // agent's key, and move the winid metadata so switching still works.
    if let Some(ref tty_val) = tty {
        let tty_trimmed = tty_val.trim();
        if !tty_trimmed.is_empty() {
            let current_action = notice.action.as_deref().map(|a| a.trim()).unwrap_or("");
            if !current_action.is_empty() {
                let active_keys: std::collections::HashSet<String> = {
                    let s = state.app.read().await;
                    s.notices
                        .iter()
                        .filter_map(|n| n.action.as_ref().map(|a| a.trim().to_string()))
                        .filter(|k| !k.is_empty())
                        .collect()
                };

                if !active_keys.contains(current_action) {
                    if let Some(matched_key) = find_session_by_tty(&active_keys, tty_trimmed) {
                        // The agent's key is new — absorb the discovered session into it.
                        // 1. Rewrite existing notices from old key → new key
                        let new_key = current_action.to_string();
                        {
                            let mut s = state.app.write().await;
                            for n in &mut s.notices {
                                if n.action.as_deref().map(|a| a.trim()) == Some(matched_key.as_str()) {
                                    n.action = Some(new_key.clone());
                                }
                            }
                        }
                        // 2. Move winid metadata: copy old file to new key, remove old
                        if let Some(home) = dirs::home_dir() {
                            let store_dir = home.join(".winids");
                            let old_path = store_dir.join(&matched_key);
                            let new_path = store_dir.join(&new_key);
                            if old_path.exists() && !new_path.exists() {
                                let _ = std::fs::copy(&old_path, &new_path);
                            }
                            let _ = std::fs::remove_file(&old_path);
                        }
                        // Keep notice.action as-is (the agent's session key)
                    }
                }
            }
        }
    }

    {
        let mut s = state.app.write().await;

        // Check rapid duplicate
        if let Some(newest) = s.notices.first() {
            if newest.is_rapid_duplicate(&notice) {
                return (
                    StatusCode::OK,
                    Json(serde_json::json!({"ok": true, "duplicate": true})),
                );
            }
        }

        s.notices.insert(0, notice.clone());
        while s.notices.len() > s.max_items {
            s.notices.pop();
        }
    }

    // Broadcast over WebSocket
    if let Ok(json) = serde_json::to_string(&NoticeSocketMessage::from(&notice)) {
        state.hub.broadcast(&json);
    }

    // Emit Tauri event for frontend
    let _ = state.app_handle.emit("notice:new", &notice);

    // System notification (skipped when the sender sets silent=true)
    if !silent {
        let s = state.app.read().await;
        system_notify::post_notice(&notice, s.no_system_notify);
    }

    // Cloud sync (background)
    {
        let s = state.app.read().await;
        if let (Some(url), Some(key)) = (s.cloud_url.clone(), s.cloud_key.clone()) {
            let notice_clone = notice.clone();
            let instance_id = s.instance_id.clone();
            tokio::spawn(async move {
                cloud_sync::sync_notice(&notice_clone, &url, &key, &instance_id).await;
            });
        }
    }

    let notice_json = serde_json::to_value(&notice).unwrap_or_default();
    (StatusCode::CREATED, Json(notice_json))
}

async fn ws_upgrade(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let hub = state.hub.clone();
    let app = state.app.clone();

    ws.on_upgrade(move |mut socket| async move {
        use axum::extract::ws::Message;

        // Send ready message
        let count = {
            let s = app.read().await;
            s.notices.len()
        };
        let ready_msg = encode_ready(count);
        let _ = socket.send(Message::Text(ready_msg.into())).await;

        // Subscribe to broadcasts
        let mut rx = hub.subscribe();

        loop {
            tokio::select! {
                msg = rx.recv() => {
                    match msg {
                        Ok(text) => {
                            if socket.send(Message::Text(text.into())).await.is_err() {
                                break;
                            }
                        }
                        Err(broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(_) => break,
                    }
                }
                incoming = socket.recv() => {
                    match incoming {
                        Some(Ok(_)) => {} // Ignore client messages
                        _ => break, // Client disconnected
                    }
                }
            }
        }
    })
    .into_response()
}

use tokio::sync::broadcast;

/// Look up a session key by matching TTY in ~/.winids/ metadata files.
fn find_session_by_tty(active_keys: &std::collections::HashSet<String>, tty: &str) -> Option<String> {
    let store_dir = dirs::home_dir()?.join(".winids");

    for key in active_keys {
        let meta_path = store_dir.join(key);
        if let Ok(contents) = std::fs::read_to_string(&meta_path) {
            for line in contents.lines() {
                if let Some(stored_tty) = line.strip_prefix("tty=") {
                    if stored_tty.trim() == tty {
                        return Some(key.clone());
                    }
                }
            }
        }
    }
    None
}

// Notepad routes

async fn post_notepad(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
    body: axum::body::Bytes,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "unauthorized"})),
        );
    }

    let payload: NotepadPayload = match serde_json::from_slice(&body) {
        Ok(p) => p,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "invalid json"})),
            );
        }
    };

    let pad = Pad::new(
        payload.title.as_deref().unwrap_or("Untitled"),
        payload.content.as_deref().unwrap_or(""),
        payload.language.as_deref().unwrap_or("markdown"),
    );

    {
        let mut s = state.app.write().await;
        s.active_pad_id = Some(pad.id);
        s.pads.push(pad.clone());
    }

    (
        StatusCode::CREATED,
        Json(serde_json::to_value(&pad).unwrap_or_default()),
    )
}

async fn get_notepad(
    State(state): State<ServerState>,
    Query(query): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let s = state.app.read().await;

    if let Some(id_str) = query.get("id") {
        if let Ok(uuid) = uuid::Uuid::parse_str(id_str) {
            if let Some(pad) = s.pads.iter().find(|p| p.id == uuid) {
                return (StatusCode::OK, Json(serde_json::to_value(pad).unwrap_or_default()));
            }
            return (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error": "not found"})),
            );
        }
    }

    let envelope = PadsEnvelope {
        pads: s.pads.clone(),
    };
    (
        StatusCode::OK,
        Json(serde_json::to_value(&envelope).unwrap_or_default()),
    )
}

async fn put_notepad(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
    body: axum::body::Bytes,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "unauthorized"})),
        );
    }

    let payload: NotepadPayload = match serde_json::from_slice(&body) {
        Ok(p) => p,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "invalid json"})),
            );
        }
    };

    let id_str = payload
        .id
        .as_deref()
        .or(query.get("id").map(|s| s.as_str()));

    let uuid = match id_str.and_then(|s| uuid::Uuid::parse_str(s).ok()) {
        Some(u) => u,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "id required"})),
            );
        }
    };

    let mut s = state.app.write().await;
    if let Some(pad) = s.pads.iter_mut().find(|p| p.id == uuid) {
        if let Some(c) = &payload.content {
            pad.content = c[..c.len().min(500_000)].to_string();
        }
        if let Some(l) = &payload.language {
            pad.language = l.clone();
        }
        if let Some(t) = &payload.title {
            pad.title = t.chars().take(200).collect();
        }
        pad.updated_at = chrono::Utc::now();
        (StatusCode::OK, Json(serde_json::json!({"ok": true})))
    } else {
        (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "not found"})),
        )
    }
}

async fn delete_notepad(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Query(query): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let secret = {
        let s = state.app.read().await;
        s.secret.clone()
    };
    if !auth_ok(&headers, &query, &secret) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "unauthorized"})),
        );
    }

    let id_str = query.get("id");
    let uuid = match id_str.and_then(|s| uuid::Uuid::parse_str(s).ok()) {
        Some(u) => u,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "id required"})),
            );
        }
    };

    let mut s = state.app.write().await;
    s.pads.retain(|p| p.id != uuid);
    if s.active_pad_id == Some(uuid) {
        s.active_pad_id = s.pads.first().map(|p| p.id);
    }
    (StatusCode::OK, Json(serde_json::json!({"ok": true})))
}
