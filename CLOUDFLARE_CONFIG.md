# Cloudflare Deployment Configuration

## ✅ Deployment Complete

The AGM Worker has been successfully deployed to Cloudflare with persistent storage (D1) and audit logging (KV).

---

## 🔐 Credentials

**Worker URL:**
```
https://agm-worker.objs.workers.dev
```

**Authentication Secret:**
```
agm_sk_9718c8a001154acd7464873ad94f2ecd
```

**D1 Database:**
- Database ID: `bf34313a-4319-41bf-b87c-f62c2cb8c743`
- Database Name: `AGM_DB`
- Tables: `notices` (persistent), `pads` (persistent)

**KV Namespace (Audit Log):**
- Namespace ID: `8af5a01a018442aa8309c5532d480fc6`
- Binding: `AUDIT_KV`
- Retention: 90 days (TTL 7,776,000 seconds)

---

## 📱 Swift App Configuration

### Option 1: Environment Variables (Recommended)

Add these to your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.config/fish/config.fish`):

```bash
export AGM_CLOUD_URL="https://agm-worker.objs.workers.dev"
export AGM_CLOUD_KEY="agm_sk_9718c8a001154acd7464873ad94f2ecd"
```

Then restart your terminal and run:
```bash
cd /Users/objsinc-macair-00/embitious/tools/agent-monitor
swift run agm
```

### Option 2: launchd Plist (For Auto-Start at Login)

Create/edit `~/Library/LaunchAgents/com.embitious.agm.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.embitious.agm</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/env</string>
        <string>bash</string>
        <string>-c</string>
        <string>source ~/.zprofile && cd /Users/objsinc-macair-00/embitious/tools/agent-monitor && swift run agm</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AGM_CLOUD_URL</key>
        <string>https://agm-worker.objs.workers.dev</string>
        <key>AGM_CLOUD_KEY</key>
        <string>agm_sk_9718c8a001154acd7464873ad94f2ecd</string>
    </dict>
</dict>
</plist>
```

Then load it:
```bash
launchctl load ~/Library/LaunchAgents/com.embitious.agm.plist
```

---

## ✅ Verification Checklist

### 1. Worker Health
```bash
curl https://agm-worker.objs.workers.dev/health
# Expected: {"ok":true,"notices":0}
```

### 2. Notice Persistence (D1)
```bash
SECRET="agm_sk_9718c8a001154acd7464873ad94f2ecd"

# POST a notice
curl -X POST https://agm-worker.objs.workers.dev/api/notices \
  -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "id":"test11111111111111111111111111",
    "instance_id":"your-machine",
    "at":"2026-03-21T14:30:00.000Z",
    "title":"Test notice",
    "body":"Persistence working"
  }'

# Expected: {"ok":true,"id":"test..."}

# Retrieve it
curl https://agm-worker.objs.workers.dev/api/notices \
  -H "Authorization: Bearer $SECRET"

# Expected: {"notifications":[{"id":"test...","title":"Test notice",...}]}
```

### 3. Audit Log (KV)
```bash
SECRET="agm_sk_9718c8a001154acd7464873ad94f2ecd"

# Write audit event
curl -X POST https://agm-worker.objs.workers.dev/api/audit \
  -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" \
  -d '[{
    "v":1,
    "id":"audit11111111111111111111111111",
    "event":"terminal.switch.succeeded",
    "at":"2026-03-21T14:31:00.000Z",
    "instanceId":"your-machine",
    "sessionId":"terminal-123",
    "result":"ok",
    "durationMs":145
  }]'

# Expected: {"ok":true,"written":1}

# Retrieve audit log
curl https://agm-worker.objs.workers.dev/api/audit?limit=5 \
  -H "Authorization: Bearer $SECRET"

# Expected: {"events":[{"v":1,"event":"terminal.switch.succeeded",...}],"cursor":null}
```

### 4. Auth Security
```bash
# This should fail (no Bearer token)
curl -X DELETE https://agm-worker.objs.workers.dev/api/notices

# Expected: {"error":"unauthorized"} with HTTP 401
```

### 5. Swift App Running
```bash
# Set env vars
export AGM_CLOUD_URL="https://agm-worker.objs.workers.dev"
export AGM_CLOUD_KEY="agm_sk_9718c8a001154acd7464873ad94f2ecd"

# Start app
cd /Users/objsinc-macair-00/embitious/tools/agent-monitor
swift run agm

# Expected output:
# • App window opens
# • HTTP server starts on port 3847
# • CloudSync reads AGM_CLOUD_URL and AGM_CLOUD_KEY
# • Background hydration loads notices from D1
# • New notices are auto-synced to D1 and KV
```

---

## 🔄 Data Flow

### When a Notice is Received

```
Agent Hook
  ↓
POST /api/notify (local HTTP server)
  ↓
PanelModel.applyAppend()
  ├─ Display in dashboard
  ├─ Post system notification
  └─ Task.detached → CloudSync.syncNotice()
       └─ Fire-and-forget POST to CF Worker /api/notices
            └─ D1: INSERT OR REPLACE (idempotent)
```

### When Terminal Switch Occurs

```
User clicks card
  ↓
PanelModel.openWinidSession()
  ├─ Per-session debounce check
  ├─ switchStatus = .switching
  ├─ Audit: auditSwitchAttempted → KV
  └─ WinidTerminalRunner.openSession()
       ├─ 16ms AppKit delay
       ├─ First attempt: winid open <id>
       ├─ If fails: 500ms wait → retry once
       ├─ 8-second hard timeout (then fail)
       └─ Callback updates switchStatus
            └─ Audit: auditSwitchResult → KV with durationMs
```

### On App Startup

```
NotifyPanelApp.onAppear
  ├─ SystemNotificationSupport.configure()
  ├─ model.startServerIfNeeded()
  ├─ Task: loadHistory()
  │    └─ CloudSync.loadHistory() → GET /api/notices from CF
  │         └─ D1: SELECT * ORDER BY at DESC LIMIT 500
  │              └─ Hydrate local items (merge, dedupe by ID)
  └─ Audit: auditAppStarted() → KV
```

---

## 🏥 Medical Compliance

### Audit Trail Coverage

✅ `app.started` — App launch
✅ `server.started` — HTTP server readiness
✅ `notice.received` — Each agent notification
✅ `notice.cleared` — Bulk clear actions
✅ `terminal.switch.attempted` — User clicked card
✅ `terminal.switch.succeeded` — Terminal focused (with duration)
✅ `terminal.switch.failed` — Failure reason + duration

### Data Retention

- **D1 (Notices)**: No automatic retention limit (permanent)
- **KV (Audit)**: 90-day TTL (adjust in `cloudflare/src/index.ts` line 159 if needed)
- **Instance ID**: Persistent at `~/.agm/instance-id` (identifies which machine)

### Security

- **Auth**: Bearer token (`AGM_SECRET`) on all write/delete operations
- **Transport**: HTTPS only (Cloudflare Workers enforce TLS)
- **Isolation**: Instance ID tags all events for multi-machine deployments
- **Rate limiting**: KV supports 1 write/ms per namespace (adequate for medical use)

---

## 🚨 Troubleshooting

### App Doesn't Sync to Cloud

**Check:**
```bash
echo $AGM_CLOUD_URL
echo $AGM_CLOUD_KEY
```

Should both be set. If not, set them in your shell profile and restart Terminal.

**Verify Worker is up:**
```bash
curl https://agm-worker.objs.workers.dev/health
```

### App Works But Cloud is Down

✅ Expected behavior! App functions normally. Audit events queue in memory (max 1000). When cloud comes back, they flush automatically.

### Auth Failures

Check the secret is exactly:
```
agm_sk_9718c8a001154acd7464873ad94f2ecd
```

No quotes, no typos. If changed via `wrangler secret put`, update `AGM_CLOUD_KEY` env var.

### Instance ID Not Persisting

Check permissions:
```bash
ls -la ~/.agm/instance-id
```

Should be readable/writable. If missing, app creates it on first run.

---

## 📊 Monitoring Audit Log

View the most recent 20 audit events:
```bash
SECRET="agm_sk_9718c8a001154acd7464873ad94f2ecd"
curl "https://agm-worker.objs.workers.dev/api/audit?limit=20" \
  -H "Authorization: Bearer $SECRET" | jq '.events'
```

Filter by event type:
```bash
curl "https://agm-worker.objs.workers.dev/api/audit?limit=50" \
  -H "Authorization: Bearer $SECRET" | jq '.events[] | select(.event == "terminal.switch.succeeded")'
```

---

## 🔄 If You Need to Reset

**Delete all notices from cloud (keeps audit log):**
```bash
SECRET="agm_sk_9718c8a001154acd7464873ad94f2ecd"
curl -X DELETE https://agm-worker.objs.workers.dev/api/notices \
  -H "Authorization: Bearer $SECRET"
```

**Delete and recreate the entire database:**
```bash
# From cloudflare/ directory
wrangler d1 delete AGM_DB
wrangler d1 create AGM_DB
# Update database_id in wrangler.toml
wrangler d1 execute AGM_DB --file=schema.sql --remote
```

---

## ✨ You're Ready!

The system is now:

✅ **Persistent** — All notices saved to D1
✅ **Audited** — Complete event trail in KV (90 days)
✅ **Reliable** — Per-session debounce, retry, 8s timeout on winid
✅ **Offline-tolerant** — Works without cloud, syncs when available
✅ **Medical-grade** — Auth, HTTPS, instance tracking, structured logging

Start the app:
```bash
export AGM_CLOUD_URL="https://agm-worker.objs.workers.dev"
export AGM_CLOUD_KEY="agm_sk_9718c8a001154acd7464873ad94f2ecd"
cd /Users/objsinc-macair-00/embitious/tools/agent-monitor
swift run agm
```

All notices and audit events will flow to Cloudflare automatically. 🚀
