use base64::Engine;

#[tauri::command]
pub async fn read_file_base64(path: String) -> Result<String, String> {
    let data = tokio::fs::read(&path)
        .await
        .map_err(|e| format!("Failed to read {}: {}", path, e))?;
    Ok(base64::engine::general_purpose::STANDARD.encode(&data))
}
