use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenSize {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowRect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Get the main display resolution.
pub async fn get_screen_size() -> Result<ScreenSize, String> {
    let py = r#"
import Quartz
b = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
print(f"{int(b.size.width)} {int(b.size.height)}")
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
    if parts.len() != 2 {
        return Err("unexpected screen size output".to_string());
    }
    Ok(ScreenSize {
        width: parts[0].parse().map_err(|_| "bad width")?,
        height: parts[1].parse().map_err(|_| "bad height")?,
    })
}

/// Compute layout rects for N windows on a given screen.
pub fn compute_layout(n: usize, layout: &str, screen: &ScreenSize) -> Vec<WindowRect> {
    let w = screen.width as i32;
    let h = screen.height as i32;
    // Reserve top menu bar area
    let top = 25;
    let usable_h = h - top;

    match layout {
        "grid" => {
            let cols = (n as f64).sqrt().ceil() as usize;
            let rows = (n + cols - 1) / cols;
            let cell_w = w / cols as i32;
            let cell_h = usable_h / rows as i32;
            (0..n)
                .map(|i| {
                    let col = (i % cols) as i32;
                    let row = (i / cols) as i32;
                    WindowRect {
                        x: col * cell_w,
                        y: top + row * cell_h,
                        width: cell_w as u32,
                        height: cell_h as u32,
                    }
                })
                .collect()
        }
        "columns" => {
            let col_w = w / n.max(1) as i32;
            (0..n)
                .map(|i| WindowRect {
                    x: i as i32 * col_w,
                    y: top,
                    width: col_w as u32,
                    height: usable_h as u32,
                })
                .collect()
        }
        "rows" => {
            let row_h = usable_h / n.max(1) as i32;
            (0..n)
                .map(|i| WindowRect {
                    x: 0,
                    y: top + i as i32 * row_h,
                    width: w as u32,
                    height: row_h as u32,
                })
                .collect()
        }
        "main-side" => {
            // First window takes left 60%, rest stack on the right 40%
            if n == 0 {
                return vec![];
            }
            let main_w = (w as f64 * 0.6) as i32;
            let side_w = w - main_w;
            let mut rects = vec![WindowRect {
                x: 0,
                y: top,
                width: main_w as u32,
                height: usable_h as u32,
            }];
            if n > 1 {
                let side_h = usable_h / (n - 1).max(1) as i32;
                for i in 0..(n - 1) {
                    rects.push(WindowRect {
                        x: main_w,
                        y: top + i as i32 * side_h,
                        width: side_w as u32,
                        height: side_h as u32,
                    });
                }
            }
            rects
        }
        _ => compute_layout(n, "grid", screen),
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
