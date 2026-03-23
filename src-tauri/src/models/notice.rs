use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Notice {
    pub id: Uuid,
    pub at: DateTime<Utc>,
    pub title: String,
    pub body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "rawResponseJSON")]
    pub raw_response_json: Option<String>,
}

impl Notice {
    pub fn make(
        title: Option<&str>,
        body: Option<&str>,
        source: Option<&str>,
        action: Option<&str>,
        summary: Option<&str>,
        request: Option<&str>,
        raw_response_json: Option<&str>,
    ) -> Self {
        let title = title
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| truncate(s, 200))
            .unwrap_or_else(|| "Notification".to_string());

        let body = body
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| truncate(s, 8000))
            .unwrap_or_else(|| "No additional details.".to_string());

        let source = trim_optional(source, 120);
        let action = trim_optional(action, 500);
        let summary = trim_optional(summary, 8000);
        let request = trim_optional(request, 4000);
        let raw_response_json = raw_response_json
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        Self {
            id: Uuid::new_v4(),
            at: Utc::now(),
            title,
            body,
            source,
            action,
            summary,
            request,
            raw_response_json,
        }
    }

    pub fn is_rapid_duplicate(&self, other: &Notice) -> bool {
        let window_secs = 2.5;
        let diff = (self.at - other.at).num_milliseconds().unsigned_abs() as f64 / 1000.0;
        if diff >= window_secs {
            return false;
        }
        self.title == other.title
            && self.body == other.body
            && self.source == other.source
            && self.action == other.action
            && self.summary == other.summary
            && self.request == other.request
            && self.raw_response_json == other.raw_response_json
    }
}

/// Flexible payload supporting multiple field name conventions.
#[derive(Debug, Deserialize)]
pub struct NotifyPayload {
    pub title: Option<String>,
    pub body: Option<String>,
    pub message: Option<String>,
    pub text: Option<String>,
    pub source: Option<String>,
    pub action: Option<String>,
    pub summary: Option<String>,
    pub request: Option<String>,
    pub raw_response_json: Option<String>,
    #[serde(rename = "rawResponseJSON")]
    pub raw_response_json_camel: Option<String>,
    pub session_id: Option<String>,
    #[serde(rename = "sessionId")]
    pub session_id_camel: Option<String>,
    /// TTY device path (e.g. "/dev/ttys003") — used to match incoming
    /// notifications to an already-discovered session.
    pub tty: Option<String>,
    /// If true, skip the macOS system notification banner.
    /// The notice is still stored and broadcast to the frontend.
    #[serde(default)]
    pub silent: bool,
}

impl NotifyPayload {
    pub fn into_notice(self) -> Notice {
        let body_text = first_non_empty(&[self.body, self.message, self.text]);
        let action = first_non_empty(&[self.action, self.session_id, self.session_id_camel]);
        let raw_json = first_non_empty(&[self.raw_response_json, self.raw_response_json_camel]);

        Notice::make(
            self.title.as_deref(),
            body_text.as_deref(),
            self.source.as_deref(),
            action.as_deref(),
            self.summary.as_deref(),
            self.request.as_deref(),
            raw_json.as_deref(),
        )
    }
}

#[derive(Serialize)]
pub struct NoticeSocketMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub id: String,
    pub at: String,
    pub title: String,
    pub body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "rawResponseJSON")]
    pub raw_response_json: Option<String>,
}

impl From<&Notice> for NoticeSocketMessage {
    fn from(n: &Notice) -> Self {
        Self {
            msg_type: "notice".to_string(),
            id: n.id.to_string(),
            at: n.at.to_rfc3339(),
            title: n.title.clone(),
            body: n.body.clone(),
            source: n.source.clone(),
            action: n.action.clone(),
            summary: n.summary.clone(),
            request: n.request.clone(),
            raw_response_json: n.raw_response_json.clone(),
        }
    }
}

#[derive(Serialize)]
pub struct NotificationsEnvelope {
    pub notifications: Vec<Notice>,
}

pub fn encode_ready(count: usize) -> String {
    format!("{{\"type\":\"ready\",\"count\":{count}}}")
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

fn trim_optional(s: Option<&str>, max: usize) -> Option<String> {
    s.map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .map(|s| truncate(&s, max))
}

fn first_non_empty(parts: &[Option<String>]) -> Option<String> {
    for part in parts {
        if let Some(s) = part {
            let trimmed = s.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    None
}
