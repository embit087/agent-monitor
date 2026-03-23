use axum::http::HeaderMap;
use std::collections::HashMap;

pub fn auth_ok(headers: &HeaderMap, query: &HashMap<String, String>, secret: &Option<String>) -> bool {
    let secret = match secret {
        Some(s) if !s.is_empty() => s,
        _ => return true,
    };

    // Check Authorization: Bearer <token>
    if let Some(auth_header) = headers.get("authorization") {
        if let Ok(val) = auth_header.to_str() {
            if let Some(token) = val.strip_prefix("Bearer ") {
                if token.trim() == secret {
                    return true;
                }
            }
        }
    }

    // Check ?token= query param
    if let Some(token) = query.get("token") {
        if token == secret {
            return true;
        }
    }

    false
}
