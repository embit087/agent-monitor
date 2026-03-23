use std::path::PathBuf;

pub fn resolve() -> Option<PathBuf> {
    let env = std::env::vars().collect::<std::collections::HashMap<_, _>>();

    // Check env overrides
    for key in &["NOTIFY_MAILBOX_WINID", "WINID_SCRIPT"] {
        if let Some(val) = env.get(*key) {
            let path = PathBuf::from(val.trim());
            if is_executable(&path) {
                return Some(path);
            }
        }
    }

    // Check AGM_PREFIX/bin/winid
    let prefix = env
        .get("AGM_PREFIX")
        .map(|s| PathBuf::from(s.trim()))
        .unwrap_or_else(|| {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".agm")
        });
    let agm_winid = prefix.join("bin").join("winid");
    if is_executable(&agm_winid) {
        return Some(agm_winid);
    }

    // Standard paths
    let candidates = [
        dirs::home_dir().map(|h| h.join(".local/bin/winid")),
        Some(PathBuf::from("/usr/local/bin/winid")),
        // Repo-adjacent fallback
        dirs::home_dir().map(|h| h.join("embitious/tools/winid")),
    ];

    for candidate in candidates.iter().flatten() {
        if is_executable(candidate) {
            return Some(candidate.clone());
        }
    }

    None
}

fn is_executable(path: &PathBuf) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.exists()
        && std::fs::metadata(path)
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}
