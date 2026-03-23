use chrono::{DateTime, Utc};
use serde::Serialize;
use std::collections::VecDeque;
use uuid::Uuid;

const MAX_PENDING: usize = 1000;

#[derive(Debug, Clone, Serialize)]
pub struct AuditEvent {
    pub v: u8,
    pub id: String,
    pub event: String,
    pub at: DateTime<Utc>,
    #[serde(rename = "instanceId")]
    pub instance_id: String,
    #[serde(skip_serializing_if = "Option::is_none", rename = "sessionId")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "noticeId")]
    pub notice_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "durationMs")]
    pub duration_ms: Option<u64>,
}

impl AuditEvent {
    pub fn new(event: &str, instance_id: &str) -> Self {
        Self {
            v: 1,
            id: Uuid::new_v4().to_string(),
            event: event.to_string(),
            at: Utc::now(),
            instance_id: instance_id.to_string(),
            session_id: None,
            notice_id: None,
            source: None,
            action: None,
            title: None,
            result: None,
            error: None,
            duration_ms: None,
        }
    }
}

pub struct AuditLog {
    pending: VecDeque<AuditEvent>,
}

impl AuditLog {
    pub fn new() -> Self {
        Self {
            pending: VecDeque::new(),
        }
    }

    pub fn enqueue(&mut self, event: AuditEvent) {
        if self.pending.len() >= MAX_PENDING {
            self.pending.pop_front();
        }
        self.pending.push_back(event);
    }

    #[allow(dead_code)]
    pub fn peek(&self, max: usize) -> Vec<AuditEvent> {
        self.pending.iter().take(max).cloned().collect()
    }

    #[allow(dead_code)]
    pub fn drain(&mut self, count: usize) {
        for _ in 0..count.min(self.pending.len()) {
            self.pending.pop_front();
        }
    }

    #[allow(dead_code)]
    pub fn pending_count(&self) -> usize {
        self.pending.len()
    }
}
