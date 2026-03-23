use crate::models::project::ProjectGroup;
use crate::state::AppState;
use std::sync::Arc;
use tokio::sync::RwLock;

#[tauri::command]
pub async fn list_projects(state: tauri::State<'_, Arc<RwLock<AppState>>>) -> Result<Vec<ProjectGroup>, String> {
    let s = state.read().await;
    s.project_db.list_projects()
}

#[tauri::command]
pub async fn create_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    name: String,
) -> Result<ProjectGroup, String> {
    let s = state.read().await;
    s.project_db.create_project(&name)
}

#[tauri::command]
pub async fn rename_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    name: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.rename_project(&id, &name)
}

#[tauri::command]
pub async fn delete_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.delete_project(&id)
}

#[tauri::command]
pub async fn set_project_color(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    hue: f64,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.set_project_color(&id, hue)
}

#[tauri::command]
pub async fn update_project_description(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    description: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.update_description(&id, &description)
}

#[tauri::command]
pub async fn update_project_directory(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    directory: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.update_directory(&id, &directory)
}

#[tauri::command]
pub async fn get_project_directory(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
) -> Result<Option<String>, String> {
    let s = state.read().await;
    s.project_db.get_project_directory(&id)
}

#[tauri::command]
pub async fn set_project_status(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    id: String,
    status: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.set_status(&id, &status)
}

#[tauri::command]
pub async fn toggle_session_in_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    session_key: String,
    group_id: String,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.toggle_session(&session_key, &group_id)
}

/// Atomically move a session to a project, or unassign if project_id is null.
#[tauri::command]
pub async fn move_session_to_project(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    session_key: String,
    project_id: Option<String>,
) -> Result<(), String> {
    let s = state.read().await;
    s.project_db.move_session(&session_key, project_id.as_deref())
}
