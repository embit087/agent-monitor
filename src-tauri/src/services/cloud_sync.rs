use crate::models::audit::AuditEvent;
use crate::models::notice::Notice;
use crate::state::AppState;
use std::sync::Arc;
use tokio::sync::RwLock;

pub async fn sync_notice(notice: &Notice, cloud_url: &str, cloud_key: &str, instance_id: &str) {
    let client = reqwest::Client::new();
    let url = format!("{cloud_url}/api/notices");

    let body = serde_json::json!({
        "id": notice.id.to_string(),
        "at": notice.at.to_rfc3339(),
        "title": notice.title,
        "body": notice.body,
        "source": notice.source,
        "action": notice.action,
        "summary": notice.summary,
        "request": notice.request,
        "rawResponseJSON": notice.raw_response_json,
        "instance_id": instance_id,
    });

    let delays = [0u64, 500, 1000, 2000];
    for (i, delay) in delays.iter().enumerate() {
        if *delay > 0 {
            tokio::time::sleep(std::time::Duration::from_millis(*delay)).await;
        }
        let result = client
            .post(&url)
            .bearer_auth(cloud_key)
            .json(&body)
            .timeout(std::time::Duration::from_secs(15))
            .send()
            .await;

        match result {
            Ok(resp) if resp.status().is_success() => return,
            Ok(_) if i < delays.len() - 1 => continue,
            Err(_) if i < delays.len() - 1 => continue,
            _ => {
                log::warn!("Failed to sync notice to cloud after retries");
                return;
            }
        }
    }
}

pub async fn load_history(
    state: Arc<RwLock<AppState>>,
    cloud_url: &str,
    cloud_key: &str,
    instance_id: &str,
) {
    let client = reqwest::Client::new();
    let url = format!("{cloud_url}/api/notices?instance_id={instance_id}&limit=500");

    let result = client
        .get(&url)
        .bearer_auth(cloud_key)
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await;

    let resp = match result {
        Ok(r) if r.status().is_success() => r,
        _ => {
            log::warn!("Failed to load cloud history");
            return;
        }
    };

    let remote_notices: Vec<Notice> = match resp.json().await {
        Ok(n) => n,
        Err(e) => {
            log::warn!("Failed to parse cloud history: {e}");
            return;
        }
    };

    if remote_notices.is_empty() {
        return;
    }

    let mut s = state.write().await;
    let existing_ids: std::collections::HashSet<_> = s.notices.iter().map(|n| n.id).collect();
    let mut incoming: Vec<Notice> = remote_notices
        .into_iter()
        .filter(|n| !existing_ids.contains(&n.id))
        .collect();

    if incoming.is_empty() {
        return;
    }

    incoming.extend(s.notices.drain(..));
    incoming.sort_by(|a, b| b.at.cmp(&a.at));
    incoming.truncate(s.max_items);
    s.notices = incoming;
}

#[allow(dead_code)]
pub async fn flush_audit_events(
    events: Vec<AuditEvent>,
    cloud_url: &str,
    cloud_key: &str,
) {
    if events.is_empty() {
        return;
    }

    let client = reqwest::Client::new();
    let url = format!("{cloud_url}/api/audit");
    let body = serde_json::json!({"events": events});

    let _ = client
        .post(&url)
        .bearer_auth(cloud_key)
        .json(&body)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await;
}
