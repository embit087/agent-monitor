use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pad {
    pub id: Uuid,
    pub title: String,
    pub content: String,
    pub language: String,
    #[serde(rename = "createdAt")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt")]
    pub updated_at: DateTime<Utc>,
}

impl Pad {
    pub fn new(title: &str, content: &str, language: &str) -> Self {
        let now = Utc::now();
        let title = {
            let t = title.trim();
            if t.is_empty() { "Untitled" } else { t }
        };
        let content = &content[..content.len().min(500_000)];

        Self {
            id: Uuid::new_v4(),
            title: title.chars().take(200).collect(),
            content: content.to_string(),
            language: language.to_string(),
            created_at: now,
            updated_at: now,
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorSettings {
    pub word_wrap: bool,
    pub minimap: bool,
    pub font_size: u8,
    pub line_numbers: bool,
}

impl Default for EditorSettings {
    fn default() -> Self {
        Self {
            word_wrap: true,
            minimap: false,
            font_size: 13,
            line_numbers: true,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct NotepadPayload {
    pub id: Option<String>,
    pub title: Option<String>,
    pub content: Option<String>,
    pub language: Option<String>,
}

#[derive(Serialize)]
pub struct PadsEnvelope {
    pub pads: Vec<Pad>,
}
