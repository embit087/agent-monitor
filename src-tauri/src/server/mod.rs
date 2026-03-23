pub mod auth;
pub mod routes;
pub mod websocket;

use crate::state::AppState;
use self::websocket::BrowserHub;
use std::sync::Arc;
use tauri::Emitter;
use tokio::sync::RwLock;

pub async fn start_http_server(
    state: Arc<RwLock<AppState>>,
    hub: BrowserHub,
    app_handle: tauri::AppHandle,
) {
    let port = {
        let s = state.read().await;
        s.port
    };

    let router = routes::create_router(state.clone(), hub, app_handle.clone());

    let addr = format!("127.0.0.1:{port}");
    let listener = match tokio::net::TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            let msg = if e.kind() == std::io::ErrorKind::AddrInUse {
                "This notification server is already running. Close the other Agent Monitor window or wait a moment, then try again.".to_string()
            } else {
                "Couldn't finish starting up. Quit and reopen the app, or try again in a few seconds.".to_string()
            };
            log::error!("Failed to bind HTTP server: {e}");
            let _ = app_handle.emit("server:error", msg);
            return;
        }
    };

    // Mark server as running
    {
        let mut s = state.write().await;
        s.server_running = true;
    }
    let _ = app_handle.emit("server:listening", port);
    eprintln!("notify-panel http://127.0.0.1:{port}/");

    if let Err(e) = axum::serve(listener, router).await {
        log::error!("HTTP server error: {e}");
        let mut s = state.write().await;
        s.server_running = false;
    }
}
