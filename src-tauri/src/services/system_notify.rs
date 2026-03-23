use crate::models::notice::Notice;

pub fn post_notice(notice: &Notice, no_system_notify: bool) {
    if no_system_notify {
        return;
    }

    let title = notice.title.clone();
    let body = notice
        .summary
        .clone()
        .or_else(|| Some(notice.body.clone()))
        .unwrap_or_default();
    let subtitle = notice.source.clone().unwrap_or_default();

    // Use osascript as a simple cross-build fallback
    std::thread::spawn(move || {
        let body_escaped = body
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .chars()
            .take(200)
            .collect::<String>();
        let title_escaped = title.replace('\\', "\\\\").replace('"', "\\\"");
        let subtitle_escaped = subtitle.replace('\\', "\\\\").replace('"', "\\\"");

        let script = format!(
            r#"display notification "{body_escaped}" with title "{title_escaped}" subtitle "{subtitle_escaped}" sound name "Glass""#,
        );

        let _ = std::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();
    });
}
