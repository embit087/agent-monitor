mod state;
mod models;
mod server;
mod commands;
mod services;

use state::AppState;
use std::sync::Arc;
use tauri::Manager;
use tokio::sync::RwLock;

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! Agent Monitor is running.", name)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            app.handle().plugin(tauri_plugin_notification::init())?;

            let app_state = Arc::new(RwLock::new(AppState::new()));
            let hub = server::websocket::BrowserHub::new(256);

            // Store state for Tauri commands
            app.manage(app_state.clone());
            app.manage(hub.clone());

            // Enqueue audit: app.started
            {
                let mut s = app_state.blocking_write();
                let event = models::audit::AuditEvent::new("app.started", &s.instance_id);
                s.audit_log.enqueue(event);
            }

            // Spawn HTTP server
            let app_handle = app.handle().clone();
            let server_state = app_state.clone();
            let server_hub = hub.clone();
            tauri::async_runtime::spawn(async move {
                server::start_http_server(server_state, server_hub, app_handle).await;
            });

            // Load cloud history in background
            let history_state = app_state.clone();
            tauri::async_runtime::spawn(async move {
                let (cloud_url, cloud_key, instance_id) = {
                    let s = history_state.read().await;
                    (s.cloud_url.clone(), s.cloud_key.clone(), s.instance_id.clone())
                };
                if let (Some(url), Some(key)) = (cloud_url, cloud_key) {
                    services::cloud_sync::load_history(history_state, &url, &key, &instance_id).await;
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            commands::notifications::get_notices,
            commands::notifications::clear_notices,
            commands::notifications::get_server_status,
            commands::notifications::send_notice,
            commands::notepad::list_pads,
            commands::notepad::create_pad,
            commands::notepad::update_pad,
            commands::notepad::delete_pad,
            commands::notepad::set_active_pad,
            commands::projects::list_projects,
            commands::projects::create_project,
            commands::projects::rename_project,
            commands::projects::delete_project,
            commands::projects::set_project_color,
            commands::projects::update_project_description,
            commands::projects::set_project_status,
            commands::projects::toggle_session_in_project,
            commands::projects::move_session_to_project,
            commands::projects::update_project_directory,
            commands::projects::get_project_directory,
            commands::winid::open_winid_session,
            commands::winid::close_winid_session,
            commands::winid::init_new_terminal,
            commands::winid::upsert_manual_terminal,
            commands::winid::capture_frontmost_session,
            commands::winid::discover_sessions,
            commands::winid::register_discovered_session,
            commands::winid::send_to_session,
            commands::winid::get_session_bounds,
            commands::winid::preview_layout,
            commands::winid::arrange_windows,
            commands::winid::cleanup_stale_sessions,
            commands::winid::save_self,
            commands::winid::focus_self,
            commands::winid::get_monitor_rect,
            commands::preview::capture_window_preview,
            commands::files::read_file_base64,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
