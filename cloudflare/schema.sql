CREATE TABLE IF NOT EXISTS notices (
    id                TEXT PRIMARY KEY,
    instance_id       TEXT NOT NULL,
    at                TEXT NOT NULL,
    title             TEXT NOT NULL,
    body              TEXT NOT NULL,
    source            TEXT,
    action            TEXT,
    summary           TEXT,
    request           TEXT,
    raw_response_json TEXT,
    synced_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_notices_at       ON notices(at DESC);
CREATE INDEX IF NOT EXISTS idx_notices_instance ON notices(instance_id, at DESC);

CREATE TABLE IF NOT EXISTS pads (
    id          TEXT PRIMARY KEY,
    instance_id TEXT NOT NULL,
    title       TEXT NOT NULL,
    content     TEXT NOT NULL,
    language    TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pads_instance ON pads(instance_id, updated_at DESC);
