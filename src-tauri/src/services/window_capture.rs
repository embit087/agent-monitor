use std::collections::HashMap;

pub fn capture_preview(session_id: &str) -> Result<String, String> {
    let metadata = read_winid_file(session_id)?;

    let app_name = metadata
        .get("app_name")
        .cloned()
        .unwrap_or_else(|| "Terminal".to_string());

    let win_name = metadata.get("win_name").cloned();

    let window_id = find_window_id(&app_name, win_name.as_deref())?;

    // Capture via screencapture -l <windowid>
    let tmp_path = format!("/tmp/agm-preview-{session_id}.png");
    let output = std::process::Command::new("screencapture")
        .args(["-l", &window_id.to_string(), "-x", &tmp_path])
        .output()
        .map_err(|e| format!("screencapture failed: {e}"))?;

    if !output.status.success() {
        return Err("screencapture failed".to_string());
    }

    let png_data = std::fs::read(&tmp_path).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&tmp_path);

    if png_data.is_empty() {
        return Err("Empty capture - screen recording permission may be needed".to_string());
    }

    use base64::Engine;
    Ok(base64::engine::general_purpose::STANDARD.encode(&png_data))
}

fn read_winid_file(session_id: &str) -> Result<HashMap<String, String>, String> {
    let home = dirs::home_dir().ok_or("cannot find home dir")?;
    let path = home.join(".winids").join(session_id);
    if !path.exists() {
        return Err(format!("No winid metadata at {}", path.display()));
    }
    let contents = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let mut map = HashMap::new();
    for line in contents.lines() {
        if let Some((key, value)) = line.split_once('=') {
            map.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    Ok(map)
}

/// Find the window ID using python3 + Quartz (PyObjC) to query CGWindowList.
fn find_window_id(app_name: &str, _win_name: Option<&str>) -> Result<u32, String> {
    let py_code = format!(
        "import Quartz\n\
         windows = Quartz.CGWindowListCopyWindowInfo(\n\
             Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,\n\
             Quartz.kCGNullWindowID\n\
         )\n\
         for w in windows:\n\
             owner = w.get('kCGWindowOwnerName', '')\n\
             layer = w.get('kCGWindowLayer', -1)\n\
             wid = w.get('kCGWindowNumber', 0)\n\
             if '{}' in owner and layer == 0:\n\
                 print(wid)\n\
                 break\n",
        app_name.replace('\'', "\\'")
    );

    let output = std::process::Command::new("python3")
        .args(["-c", &py_code])
        .output()
        .map_err(|e| format!("python3 failed: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    stdout
        .parse::<u32>()
        .map_err(|_| format!("Could not find window for {app_name}"))
}
