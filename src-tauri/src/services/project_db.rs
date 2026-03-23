use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use std::sync::Mutex;

use crate::models::project::{ProjectGroup, ProjectStatus};

/// In-memory SQLite database for project management.
/// Wiped on every app restart (no persistence).
pub struct ProjectDb {
    conn: Mutex<Connection>,
}

impl ProjectDb {
    pub fn new() -> Self {
        let conn = Connection::open_in_memory().expect("failed to open in-memory SQLite");
        conn.execute_batch(
            "
            CREATE TABLE projects (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                color_hue   REAL NOT NULL DEFAULT 0.0,
                description TEXT,
                directory   TEXT,
                status      TEXT NOT NULL DEFAULT 'active',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );

            CREATE TABLE project_sessions (
                project_id  TEXT NOT NULL,
                session_key TEXT NOT NULL,
                PRIMARY KEY (project_id, session_key),
                FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            -- Each session can only belong to one project
            CREATE UNIQUE INDEX idx_session_unique ON project_sessions(session_key);
            ",
        )
        .expect("failed to create project tables");

        // Enable foreign keys
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .expect("failed to enable foreign keys");

        Self {
            conn: Mutex::new(conn),
        }
    }

    pub fn list_projects(&self) -> Result<Vec<ProjectGroup>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;

        let mut stmt = conn
            .prepare(
                "SELECT id, name, color_hue, description, directory, status, created_at, updated_at
                 FROM projects ORDER BY created_at ASC",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map([], |row| {
                let id_str: String = row.get(0)?;
                let name: String = row.get(1)?;
                let color_hue: f64 = row.get(2)?;
                let description: Option<String> = row.get(3)?;
                let directory: Option<String> = row.get(4)?;
                let status_str: String = row.get(5)?;
                let created_at_str: String = row.get(6)?;
                let updated_at_str: String = row.get(7)?;

                Ok((
                    id_str,
                    name,
                    color_hue,
                    description,
                    directory,
                    status_str,
                    created_at_str,
                    updated_at_str,
                ))
            })
            .map_err(|e| e.to_string())?;

        let mut projects = Vec::new();
        for row in rows {
            let (id_str, name, color_hue, description, directory, status_str, created_at_str, updated_at_str) =
                row.map_err(|e| e.to_string())?;

            let id = uuid::Uuid::parse_str(&id_str).map_err(|e| e.to_string())?;
            let status = match status_str.as_str() {
                "archived" => ProjectStatus::Archived,
                _ => ProjectStatus::Active,
            };
            let created_at: DateTime<Utc> = created_at_str
                .parse()
                .unwrap_or_else(|_| Utc::now());
            let updated_at: DateTime<Utc> = updated_at_str
                .parse()
                .unwrap_or_else(|_| Utc::now());

            // Fetch session keys for this project
            let mut key_stmt = conn
                .prepare("SELECT session_key FROM project_sessions WHERE project_id = ?1")
                .map_err(|e| e.to_string())?;
            let keys: Vec<String> = key_stmt
                .query_map(params![&id_str], |r| r.get(0))
                .map_err(|e| e.to_string())?
                .filter_map(|r| r.ok())
                .collect();

            projects.push(ProjectGroup {
                id,
                name,
                color_hue,
                session_keys: keys.into_iter().collect(),
                description,
                directory,
                status,
                created_at,
                updated_at,
            });
        }

        Ok(projects)
    }

    pub fn create_project(&self, name: &str) -> Result<ProjectGroup, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let group = ProjectGroup::new(name);
        let id_str = group.id.to_string();
        let status_str = match group.status {
            ProjectStatus::Active => "active",
            ProjectStatus::Archived => "archived",
        };

        conn.execute(
            "INSERT INTO projects (id, name, color_hue, description, directory, status, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id_str,
                group.name,
                group.color_hue,
                group.description,
                group.directory,
                status_str,
                group.created_at.to_rfc3339(),
                group.updated_at.to_rfc3339(),
            ],
        )
        .map_err(|e| e.to_string())?;

        Ok(group)
    }

    pub fn rename_project(&self, id: &str, name: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let now = Utc::now().to_rfc3339();
        let affected = conn
            .execute(
                "UPDATE projects SET name = ?1, updated_at = ?2 WHERE id = ?3",
                params![name.trim(), now, id],
            )
            .map_err(|e| e.to_string())?;
        if affected == 0 {
            return Err("not found".to_string());
        }
        Ok(())
    }

    pub fn delete_project(&self, id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        // Delete session associations first, then the project
        conn.execute(
            "DELETE FROM project_sessions WHERE project_id = ?1",
            params![id],
        )
        .map_err(|e| e.to_string())?;
        conn.execute("DELETE FROM projects WHERE id = ?1", params![id])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn set_project_color(&self, id: &str, hue: f64) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let now = Utc::now().to_rfc3339();
        let affected = conn
            .execute(
                "UPDATE projects SET color_hue = ?1, updated_at = ?2 WHERE id = ?3",
                params![hue, now, id],
            )
            .map_err(|e| e.to_string())?;
        if affected == 0 {
            return Err("not found".to_string());
        }
        Ok(())
    }

    pub fn update_description(&self, id: &str, description: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let now = Utc::now().to_rfc3339();
        let desc = if description.trim().is_empty() {
            None
        } else {
            Some(description.trim().to_string())
        };
        let affected = conn
            .execute(
                "UPDATE projects SET description = ?1, updated_at = ?2 WHERE id = ?3",
                params![desc, now, id],
            )
            .map_err(|e| e.to_string())?;
        if affected == 0 {
            return Err("not found".to_string());
        }
        Ok(())
    }

    pub fn update_directory(&self, id: &str, directory: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let now = Utc::now().to_rfc3339();
        let dir = if directory.trim().is_empty() {
            None
        } else {
            Some(directory.trim().to_string())
        };
        let affected = conn
            .execute(
                "UPDATE projects SET directory = ?1, updated_at = ?2 WHERE id = ?3",
                params![dir, now, id],
            )
            .map_err(|e| e.to_string())?;
        if affected == 0 {
            return Err("not found".to_string());
        }
        Ok(())
    }

    /// Get the directory for a specific project.
    pub fn get_project_directory(&self, id: &str) -> Result<Option<String>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.query_row(
            "SELECT directory FROM projects WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())
    }

    pub fn set_status(&self, id: &str, status: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let now = Utc::now().to_rfc3339();
        match status {
            "active" | "archived" => {}
            _ => return Err(format!("invalid status: {status}")),
        }
        let affected = conn
            .execute(
                "UPDATE projects SET status = ?1, updated_at = ?2 WHERE id = ?3",
                params![status, now, id],
            )
            .map_err(|e| e.to_string())?;
        if affected == 0 {
            return Err("not found".to_string());
        }
        Ok(())
    }

    /// Toggle a session in/out of a project.
    /// A session can only belong to one project at a time.
    pub fn toggle_session(&self, session_key: &str, project_id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let key = session_key.trim();

        // Check if already in this project
        let exists: bool = conn
            .query_row(
                "SELECT COUNT(*) FROM project_sessions WHERE project_id = ?1 AND session_key = ?2",
                params![project_id, key],
                |row| row.get::<_, i64>(0),
            )
            .map(|c| c > 0)
            .map_err(|e| e.to_string())?;

        if exists {
            // Remove from this project
            conn.execute(
                "DELETE FROM project_sessions WHERE project_id = ?1 AND session_key = ?2",
                params![project_id, key],
            )
            .map_err(|e| e.to_string())?;
        } else {
            // Remove from any other project first (unique constraint)
            conn.execute(
                "DELETE FROM project_sessions WHERE session_key = ?1",
                params![key],
            )
            .map_err(|e| e.to_string())?;
            // Add to target project
            conn.execute(
                "INSERT INTO project_sessions (project_id, session_key) VALUES (?1, ?2)",
                params![project_id, key],
            )
            .map_err(|e| e.to_string())?;
        }

        // Touch updated_at
        let now = Utc::now().to_rfc3339();
        conn.execute(
            "UPDATE projects SET updated_at = ?1 WHERE id = ?2",
            params![now, project_id],
        )
        .map_err(|e| e.to_string())?;

        Ok(())
    }

    /// Move a session to a specific project, or unassign if project_id is None.
    /// This is an atomic operation — no race conditions.
    pub fn move_session(&self, session_key: &str, project_id: Option<&str>) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let key = session_key.trim();
        let now = Utc::now().to_rfc3339();

        // Remove from any current project
        conn.execute(
            "DELETE FROM project_sessions WHERE session_key = ?1",
            params![key],
        )
        .map_err(|e| e.to_string())?;

        // Add to new project if specified
        if let Some(pid) = project_id {
            // Verify project exists
            let exists: bool = conn
                .query_row(
                    "SELECT COUNT(*) FROM projects WHERE id = ?1",
                    params![pid],
                    |row| row.get::<_, i64>(0),
                )
                .map(|c| c > 0)
                .map_err(|e| e.to_string())?;

            if !exists {
                return Err("project not found".to_string());
            }

            conn.execute(
                "INSERT INTO project_sessions (project_id, session_key) VALUES (?1, ?2)",
                params![pid, key],
            )
            .map_err(|e| e.to_string())?;

            conn.execute(
                "UPDATE projects SET updated_at = ?1 WHERE id = ?2",
                params![now, pid],
            )
            .map_err(|e| e.to_string())?;
        }

        Ok(())
    }
}
