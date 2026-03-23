use crate::models::notice::Notice;
use crate::models::pad::Pad;
use crate::models::audit::AuditLog;
use crate::services::winid_locator;
use crate::services::project_db::ProjectDb;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Instant;

pub struct AppState {
    pub notices: Vec<Notice>,
    pub pads: Vec<Pad>,
    pub active_pad_id: Option<uuid::Uuid>,
    pub project_db: ProjectDb,
    pub server_running: bool,
    pub port: u16,
    pub max_items: usize,
    pub secret: Option<String>,
    pub switch_times: HashMap<String, Instant>,
    pub winid_path: Option<PathBuf>,
    pub audit_log: AuditLog,
    pub cloud_url: Option<String>,
    pub cloud_key: Option<String>,
    pub instance_id: String,
    pub no_system_notify: bool,
}

impl AppState {
    pub fn new() -> Self {
        let port = std::env::var("NOTIFY_MAILBOX_PORT")
            .ok()
            .and_then(|s| s.parse::<u16>().ok())
            .filter(|&p| p > 0)
            .or_else(|| {
                std::env::var("PORT")
                    .ok()
                    .and_then(|s| s.parse::<u16>().ok())
                    .filter(|&p| p > 0)
            })
            .unwrap_or(3850);

        let raw_max = std::env::var("NOTIFY_MAILBOX_MAX")
            .ok()
            .and_then(|s| s.parse::<usize>().ok())
            .unwrap_or(500);
        let max_items = raw_max.clamp(1, 5000);

        let secret = std::env::var("NOTIFY_MAILBOX_SECRET")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let winid_path = winid_locator::resolve();

        let cloud_url = std::env::var("AGM_CLOUD_URL")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let cloud_key = std::env::var("AGM_CLOUD_KEY")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let instance_id = crate::services::instance_id::get_or_create();

        let no_system_notify = std::env::var("NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY")
            .ok()
            .map(|s| matches!(s.to_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false);

        let project_db = ProjectDb::new();

        Self {
            notices: Vec::new(),
            pads: Vec::new(),
            active_pad_id: None,
            project_db,
            server_running: false,
            port,
            max_items,
            secret,
            switch_times: HashMap::new(),
            winid_path,
            audit_log: AuditLog::new(),
            cloud_url,
            cloud_key,
            instance_id,
            no_system_notify,
        }
    }
}
