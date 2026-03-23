use crate::models::project::ProjectGroup;
use crate::state::AppState;
use std::sync::Arc;
use tokio::sync::RwLock;

#[tauri::command]
pub async fn list_projects(state: tauri::State<'_, Arc<RwLock<AppState>>>) -> Result<Vec<ProjectGroup>, String> {
    let s = state.read().await;
    Ok(s.projects.clone())
}

#[tauri::command]
pub async fn create_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    name: String,
) -> Result<ProjectGroup, String> {
    let group = ProjectGroup::new(&name);
    let mut s = state.write().await;
    s.projects.push(group.clone());
    ProjectGroup::save_to_disk(&s.projects)?;
    Ok(group)
}

#[tauri::command]
pub async fn rename_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    name: String,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    let group = s.projects.iter_mut().find(|g| g.id == uuid).ok_or("not found")?;
    group.name = name.trim().to_string();
    ProjectGroup::save_to_disk(&s.projects)?;
    Ok(())
}

#[tauri::command]
pub async fn delete_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    s.projects.retain(|g| g.id != uuid);
    ProjectGroup::save_to_disk(&s.projects)?;
    Ok(())
}

#[tauri::command]
pub async fn set_project_color(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    hue: f64,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut s = state.write().await;
    let group = s.projects.iter_mut().find(|g| g.id == uuid).ok_or("not found")?;
    group.color_hue = hue;
    ProjectGroup::save_to_disk(&s.projects)?;
    Ok(())
}

#[tauri::command]
pub async fn toggle_session_in_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    session_key: String,
    group_id: String,
) -> Result<(), String> {
    let uuid = uuid::Uuid::parse_str(&group_id).map_err(|e| e.to_string())?;
    let key = session_key.trim().to_string();
    let mut s = state.write().await;

    // Remove from all other projects first (one session per project)
    for g in s.projects.iter_mut() {
        if g.id != uuid {
            g.session_keys.remove(&key);
        }
    }

    // Toggle in target project
    let group = s.projects.iter_mut().find(|g| g.id == uuid).ok_or("not found")?;
    if group.session_keys.contains(&key) {
        group.session_keys.remove(&key);
    } else {
        group.session_keys.insert(key);
    }

    ProjectGroup::save_to_disk(&s.projects)?;
    Ok(())
}
