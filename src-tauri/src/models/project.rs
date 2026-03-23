use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ProjectStatus {
    Active,
    Archived,
}

impl Default for ProjectStatus {
    fn default() -> Self {
        Self::Active
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectGroup {
    pub id: Uuid,
    pub name: String,
    #[serde(rename = "colorHue")]
    pub color_hue: f64,
    #[serde(rename = "sessionKeys")]
    pub session_keys: HashSet<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub directory: Option<String>,
    #[serde(default = "ProjectStatus::default")]
    pub status: ProjectStatus,
    #[serde(rename = "createdAt")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt", default = "Utc::now")]
    pub updated_at: DateTime<Utc>,
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
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            name: name.trim().to_string(),
            color_hue: HUE_PALETTE[0],
            session_keys: HashSet::new(),
            description: None,
            directory: None,
            status: ProjectStatus::Active,
            created_at: now,
            updated_at: now,
        }
    }
}
