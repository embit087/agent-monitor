use serde::Serialize;

#[derive(Serialize)]
pub struct PreviewResult {
    pub ok: bool,
    pub image: Option<String>,
    pub error: Option<String>,
}

#[tauri::command]
pub async fn capture_window_preview(session_id: String) -> Result<PreviewResult, String> {
    let id = session_id.trim().to_string();
    if id.is_empty() {
        return Ok(PreviewResult {
            ok: false,
            image: None,
            error: Some("empty session id".to_string()),
        });
    }

    match crate::services::window_capture::capture_preview(&id) {
        Ok(base64_png) => Ok(PreviewResult {
            ok: true,
            image: Some(base64_png),
            error: None,
        }),
        Err(msg) => Ok(PreviewResult {
            ok: false,
            image: None,
            error: Some(msg),
        }),
    }
}
