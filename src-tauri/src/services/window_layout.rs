use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenSize {
    pub width: u32,
    pub height: u32,
    /// Usable area origin X (e.g. dock on left shifts this)
    pub visible_x: i32,
    /// Usable area origin Y (menu bar shifts this)
    pub visible_y: i32,
    /// Usable area width (excludes dock if on side)
    pub visible_width: u32,
    /// Usable area height (excludes menu bar + dock)
    pub visible_height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowRect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Get the main display resolution and usable area (excluding menu bar and dock).
pub async fn get_screen_size() -> Result<ScreenSize, String> {
    // NSScreen.visibleFrame() excludes menu bar and dock.
    // Note: NSScreen uses bottom-left origin, so we convert to top-left.
    let py = r#"
from AppKit import NSScreen
s = NSScreen.mainScreen()
f = s.frame()
v = s.visibleFrame()
sw = int(f.size.width)
sh = int(f.size.height)
# Convert from bottom-left to top-left coordinate system
vy = int(sh - v.origin.y - v.size.height)
vx = int(v.origin.x)
vw = int(v.size.width)
vh = int(v.size.height)
print(f"{sw} {sh} {vx} {vy} {vw} {vh}")
"#;
    let output = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("python3")
            .args(["-c", py])
            .output()
            .await
    })
    .await
    .map_err(|_| "timeout")?
    .map_err(|e| format!("python3 error: {e}"))?;

    let s = String::from_utf8_lossy(&output.stdout);
    let parts: Vec<&str> = s.trim().split_whitespace().collect();
    if parts.len() != 6 {
        return Err(format!("unexpected screen output: {s}"));
    }
    Ok(ScreenSize {
        width: parts[0].parse().map_err(|_| "bad width")?,
        height: parts[1].parse().map_err(|_| "bad height")?,
        visible_x: parts[2].parse().map_err(|_| "bad vx")?,
        visible_y: parts[3].parse().map_err(|_| "bad vy")?,
        visible_width: parts[4].parse().map_err(|_| "bad vw")?,
        visible_height: parts[5].parse().map_err(|_| "bad vh")?,
    })
}

/// Compute layout rects for N windows using the full visible screen area
/// (excludes menu bar + dock, but uses the entire remaining space).
///
/// When `exclude` is provided, the excluded rect's area is subtracted from
/// the nearest screen edge so that agent windows tile around it.
pub fn compute_layout(
    n: usize,
    layout: &str,
    screen: &ScreenSize,
    exclude: Option<&WindowRect>,
) -> Vec<WindowRect> {
    let mut ax = screen.visible_x;
    let mut ay = screen.visible_y;
    let mut aw = screen.visible_width as i32;
    let mut ah = screen.visible_height as i32;

    if let Some(ex) = exclude {
        let ex_right = ex.x + ex.width as i32;
        let ex_bottom = ex.y + ex.height as i32;
        let screen_right = ax + aw;
        let screen_bottom = ay + ah;

        // Determine which screen edge the excluded rect is closest to
        let dist_left = (ex.x - ax).abs();
        let dist_right = (screen_right - ex_right).abs();
        let dist_top = (ex.y - ay).abs();
        let dist_bottom = (screen_bottom - ex_bottom).abs();
        let min_dist = dist_left.min(dist_right).min(dist_top).min(dist_bottom);

        if min_dist == dist_left {
            let new_ax = ex_right;
            aw -= new_ax - ax;
            ax = new_ax;
        } else if min_dist == dist_right {
            aw = ex.x - ax;
        } else if min_dist == dist_top {
            let new_ay = ex_bottom;
            ah -= new_ay - ay;
            ay = new_ay;
        } else {
            ah = ex.y - ay;
        }

        // Clamp to sane minimums
        if aw < 100 { aw = 100; }
        if ah < 100 { ah = 100; }
    }

    match layout {
        "grid" => {
            let cols = (n as f64).sqrt().ceil() as usize;
            let rows = (n + cols - 1) / cols;
            let cell_w = aw / cols as i32;
            let cell_h = ah / rows as i32;
            (0..n)
                .map(|i| {
                    let col = (i % cols) as i32;
                    let row = (i / cols) as i32;
                    WindowRect {
                        x: ax + col * cell_w,
                        y: ay + row * cell_h,
                        width: cell_w as u32,
                        height: cell_h as u32,
                    }
                })
                .collect()
        }
        "columns" => {
            let col_w = aw / n.max(1) as i32;
            (0..n)
                .map(|i| WindowRect {
                    x: ax + i as i32 * col_w,
                    y: ay,
                    width: col_w as u32,
                    height: ah as u32,
                })
                .collect()
        }
        "rows" => {
            let row_h = ah / n.max(1) as i32;
            (0..n)
                .map(|i| WindowRect {
                    x: ax,
                    y: ay + i as i32 * row_h,
                    width: aw as u32,
                    height: row_h as u32,
                })
                .collect()
        }
        "main-side" => {
            if n == 0 {
                return vec![];
            }
            let main_w = (aw as f64 * 0.6) as i32;
            let side_w = aw - main_w;
            let mut rects = vec![WindowRect {
                x: ax,
                y: ay,
                width: main_w as u32,
                height: ah as u32,
            }];
            if n > 1 {
                let side_h = ah / (n - 1).max(1) as i32;
                for i in 0..(n - 1) {
                    rects.push(WindowRect {
                        x: ax + main_w,
                        y: ay + i as i32 * side_h,
                        width: side_w as u32,
                        height: side_h as u32,
                    });
                }
            }
            rects
        }
        _ => compute_layout(n, "grid", screen, exclude),
    }
}

/// Get the current bounds of a window by app name and window title.
pub async fn get_window_bounds_by_title(app_name: &str, win_title: &str) -> Result<WindowRect, String> {
    let title_escaped = win_title.replace('\\', "\\\\").replace('"', "\\\"");
    let app_escaped = app_name.replace('\\', "\\\\").replace('"', "\\\"");

    let script = format!(
        r#"tell application "System Events"
    tell process "{app_escaped}"
        repeat with w in windows
            if name of w contains "{title_escaped}" then
                set pos to position of w
                set sz to size of w
                return "" & (item 1 of pos) & " " & (item 2 of pos) & " " & (item 1 of sz) & " " & (item 2 of sz)
            end if
        end repeat
    end tell
end tell
return "not found""#
    );

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if stdout == "not found" || stdout.is_empty() {
                return Err(format!("Window not found: {win_title}"));
            }
            let parts: Vec<&str> = stdout.split_whitespace().collect();
            if parts.len() != 4 {
                return Err(format!("unexpected output: {stdout}"));
            }
            Ok(WindowRect {
                x: parts[0].parse().map_err(|_| "bad x")?,
                y: parts[1].parse().map_err(|_| "bad y")?,
                width: parts[2].parse().map_err(|_| "bad w")?,
                height: parts[3].parse().map_err(|_| "bad h")?,
            })
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("timeout".to_string()),
    }
}

/// Get the current bounds of a Terminal.app window by TTY.
pub async fn get_terminal_bounds_by_tty(tty: &str) -> Result<WindowRect, String> {
    let script = format!(
        r#"tell application "Terminal"
    repeat with w in windows
        repeat with t in tabs of w
            try
                if tty of t is "{tty}" then
                    set b to bounds of w
                    return "" & (item 1 of b) & " " & (item 2 of b) & " " & ((item 3 of b) - (item 1 of b)) & " " & ((item 4 of b) - (item 2 of b))
                end if
            end try
        end repeat
    end repeat
end tell
return "not found""#
    );

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if stdout == "not found" || stdout.is_empty() {
                return Err(format!("Terminal with tty {tty} not found"));
            }
            let parts: Vec<&str> = stdout.split_whitespace().collect();
            if parts.len() != 4 {
                return Err(format!("unexpected output: {stdout}"));
            }
            Ok(WindowRect {
                x: parts[0].parse().map_err(|_| "bad x")?,
                y: parts[1].parse().map_err(|_| "bad y")?,
                width: parts[2].parse().map_err(|_| "bad w")?,
                height: parts[3].parse().map_err(|_| "bad h")?,
            })
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("timeout".to_string()),
    }
}

/// Move and resize a window identified by app name and window title.
pub async fn set_window_bounds(
    app_name: &str,
    win_title: &str,
    rect: &WindowRect,
) -> Result<(), String> {
    // Escape for AppleScript
    let title_escaped = win_title.replace('\\', "\\\\").replace('"', "\\\"");
    let app_escaped = app_name.replace('\\', "\\\\").replace('"', "\\\"");

    let script = format!(
        r#"tell application "System Events"
    tell process "{app_escaped}"
        repeat with w in windows
            if name of w contains "{title_escaped}" then
                set position of w to {{{}, {}}}
                set size of w to {{{}, {}}}
                return "ok"
            end if
        end repeat
    end tell
end tell
return "not found""#,
        rect.x, rect.y, rect.width, rect.height
    );

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.trim() == "ok" {
                Ok(())
            } else if output.status.success() {
                Err(format!("Window not found: {win_title}"))
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                Err(format!("AppleScript error: {stderr}"))
            }
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("timeout".to_string()),
    }
}

/// Move a Terminal.app window by matching its TTY.
pub async fn set_terminal_bounds_by_tty(
    tty: &str,
    rect: &WindowRect,
) -> Result<(), String> {
    let script = format!(
        r#"tell application "Terminal"
    repeat with w in windows
        repeat with t in tabs of w
            try
                if tty of t is "{tty}" then
                    set bounds of w to {{{}, {}, {}, {}}}
                    return "ok"
                end if
            end try
        end repeat
    end repeat
end tell
return "not found""#,
        rect.x, rect.y, rect.x as i32 + rect.width as i32, rect.y as i32 + rect.height as i32
    );

    let result = tokio::time::timeout(Duration::from_secs(5), async {
        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
            .await
    })
    .await;

    match result {
        Ok(Ok(output)) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.trim() == "ok" {
                Ok(())
            } else {
                Err(format!("Terminal with tty {tty} not found"))
            }
        }
        Ok(Err(e)) => Err(format!("osascript error: {e}")),
        Err(_) => Err("timeout".to_string()),
    }
}
