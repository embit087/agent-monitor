use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectGroup {
    pub id: Uuid,
    pub name: String,
    #[serde(rename = "colorHue")]
    pub color_hue: f64,
    #[serde(rename = "sessionKeys")]
    pub session_keys: HashSet<String>,
    #[serde(rename = "createdAt")]
    pub created_at: DateTime<Utc>,
}

/// The 9-color hue palette matching the Swift version.
pub const HUE_PALETTE: [f64; 9] = [
    0.0,    // red
    0.08,   // orange
    0.15,   // yellow
    0.33,   // green
    0.5,    // teal
    0.6,    // blue
    0.72,   // indigo
    0.8,    // purple
    0.9,    // pink
];

impl ProjectGroup {
    pub fn new(name: &str) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.trim().to_string(),
            color_hue: HUE_PALETTE[0],
            session_keys: HashSet::new(),
            created_at: Utc::now(),
        }
    }

    fn storage_path() -> PathBuf {
        let prefix = std::env::var("AGM_PREFIX")
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                dirs::home_dir()
                    .unwrap_or_else(|| PathBuf::from("."))
                    .join(".agm")
            });
        prefix.join("projects.json")
    }

    pub fn load_from_disk() -> Result<Vec<ProjectGroup>, String> {
        let path = Self::storage_path();
        if !path.exists() {
            return Ok(Vec::new());
        }
        let data = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
        serde_json::from_str(&data).map_err(|e| e.to_string())
    }

    pub fn save_to_disk(groups: &[ProjectGroup]) -> Result<(), String> {
        let path = Self::storage_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let data = serde_json::to_string_pretty(groups).map_err(|e| e.to_string())?;
        std::fs::write(&path, data).map_err(|e| e.to_string())
    }
}
