use crate::models::pad::Pad;
use crate::state::AppState;
use std::sync::Arc;
use tokio::sync::RwLock;

#[tauri::command]
pub async fn list_pads(state: tauri::State<'_, Arc<RwLock<AppState>>>) -> Result<Vec<Pad>, String> {
    let s = state.read().await;
    Ok(s.pads.clone())
}

#[tauri::command]
pub async fn create_pad(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    title: String,
    content: String,
    language: String,
) -> Result<Pad, String> {
    let pad = Pad::new(&title, &content, &language);
    let mut s = state.write().await;
    s.active_pad_id = Some(pad.id);
    s.pads.push(pad.clone());
    Ok(pad)
}

#[tauri::command]
pub async fn update_pad(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    title: Option<String>,
    content: Option<String>,
    language: Option<String>,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    let pad = s.pads.iter_mut().find(|p| p.id == uuid).ok_or("not found")?;
    if let Some(t) = title {
        pad.title = t.chars().take(200).collect();
    }
    if let Some(c) = content {
        pad.content = c[..c.len().min(500_000)].to_string();
    }
    if let Some(l) = language {
        pad.language = l;
    }
    pad.updated_at = chrono::Utc::now();
    Ok(())
}

#[tauri::command]
pub async fn delete_pad(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    s.pads.retain(|p| p.id != uuid);
    if s.active_pad_id == Some(uuid) {
        s.active_pad_id = s.pads.first().map(|p| p.id);
    }
    Ok(())
}

#[tauri::command]
pub async fn set_active_pad(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    if s.pads.iter().any(|p| p.id == uuid) {
        s.active_pad_id = Some(uuid);
        Ok(())
    } else {
        Err("not found".to_string())
    }
}
