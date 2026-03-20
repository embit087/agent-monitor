# Notify Panel (Swift)

macOS app (**SwiftUI**) with an embedded **FlyingFox** HTTP server on **127.0.0.1**. It accepts `POST /api/notify` from **Claude Code** hooks, **Cursor Agent** hooks, or **`curl`**, shows items in the app window, and streams live updates over **WebSocket** (`GET /api/ws`) for any client you build.

When a hook finishes, **`notify-post.sh`** sends the stable id (**`session_id`** or **`conversation_id`**) as `action`. **Switch agent** runs `winid open <id>` in **Terminal.app** (`bash -lc` with an explicit `winid` path when found, otherwise **`bash -il -c`** so `winid` on your login `PATH` works).

Additional docs:

- [`overview.md`](overview.md) — architecture and component map
- [`pty-launcher-guide.md`](pty-launcher-guide.md) — implementation guide for moving from hook-driven sessions to a PTY-backed launcher

## Requirements

- macOS 14+
- Swift 5.10+ (Xcode 15.4+)

## Setup (one command)

From this directory:

```bash
bash scripts/setup-notify-panel.sh
```

This **chmod**s the hook scripts, **merges** Cursor user hooks (`~/.cursor/hooks.json`), **rewrites** legacy Claude hook paths in `~/.claude/settings.json` if they still mention `claude-*-mailbox.sh`, runs **`swift build`**, checks **winid**, and prints next steps. Use `bash scripts/setup-notify-panel.sh --no-build` or `--no-cursor` to skip those steps.

## Run

```bash
cd agent-monitor
swift run NotifyPanel
```

The app window opens; the server listens on **3847** by default. Stderr logs: `notify-panel http://127.0.0.1:3847/`

### Claude Code integration (recommended)

Claude Code sends **hook JSON on stdin** for every event; common fields include **`session_id`** ([hooks reference](https://code.claude.com/docs/en/hooks#hook-input-and-output)).

1. **SessionStart** — register the frontmost window (your Terminal tab running Claude) under that session id:
   - `scripts/winid-session-register.sh` → `winid save <session_id>`.

2. **`Stop` hook** (Claude Code lifecycle) — **`notify-post.sh`** reads stdin JSON, extracts `session_id`, `POST`s to `/api/notify` as `action`.

If SessionStart never ran, `winid open <session_id>` has nothing to focus — keep **both** hooks.

Example `settings.json` fragment (fix paths):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/you/embitious/tools/agent-monitor/scripts/winid-session-register.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/you/embitious/tools/agent-monitor/scripts/notify-post.sh \"Claude Code\" \"Turn complete\""
          }
        ]
      }
    ]
  }
}
```

### Cursor CLI / Agent (project hooks)

This repo ships **`.cursor/hooks.json`** for [Cursor Agent hooks](https://cursor.com/docs/agent/hooks) when you open this folder as the **workspace root** (path is still `tools/agent-monitor` in the monorepo):

- **`sessionStart`** → `scripts/winid-session-register.sh` (reads **`conversation_id`** from Cursor’s stdin JSON and runs `winid save …`)
- **`stop`** → `.cursor/hooks/cursor-stop-notify.sh` → `notify-post.sh` (same POST as Claude; wrapper hides **curl** stdout and prints `{}` so Cursor gets a valid **stop** hook response)

Mark the workspace **trusted** so project hooks run. If you already have a project `hooks.json`, merge these `sessionStart` / `stop` entries instead of replacing the file. In a monorepo, add equivalent commands at the repo root and point them at `tools/agent-monitor/scripts/…`.

#### Cursor CLI from another terminal / any workspace

Project hooks **do not** load if the workspace root is not this repo (e.g. you run Cursor Agent from a different folder). Install **user** hooks so `sessionStart` / `stop` always resolve:

```bash
bash scripts/install-cursor-notify-hooks.sh
```

This merges **`~/.cursor/hooks.json`** with absolute paths to these scripts (and sets **`loop_limit`: `null`** on the panel `stop` entry so it is not capped by Cursor’s default). Restart Cursor or start a **new** agent session after installing.

An Agent Skill in **`.cursor/skills/install-cursor-notify-hooks/`** describes how to run this installer.

```bash
chmod +x scripts/notify-post.sh scripts/winid-session-register.sh .cursor/hooks/cursor-stop-notify.sh scripts/install-cursor-notify-hooks.sh
```

When stdin is hook JSON (not a TTY), **`notify-post.sh` picks `session_id`, then `conversation_id`, then `sessionId`**. From an interactive shell (TTY stdin), it **falls back** to `WINID_SESSION_UUID` / `winid session`.

| Env | Role |
|-----|------|
| `NOTIFY_MAILBOX_WINID` | Optional override for the `winid` path. If unset, the app tries `WINID_SCRIPT`, `~/embitious/tools/winid`, `~/tools/winid`, and (when built from this repo) **`tools/winid`** next to the package. |
| `WINID_SCRIPT` | Optional; where to find `winid` for the shell scripts when it’s not on `PATH`. |
| `MAILBOX_PREFER_WINID` | If `1`, **`notify-post.sh`** ignores hook ids (`session_id` / `conversation_id`) and uses Fish/winid id only (legacy variable name). |
| `WINID_SESSION_UUID` | Fish winid integration; notify script fallback when stdin is TTY. |
| `CLAUDE_CODE_SESSION_ID` | Optional; if set in the app’s environment, pre-fills session field (advanced). |
| `NOTIFY_MAILBOX_TEST_SESSION` | Optional manual override for testing. |

If no default path finds an executable `winid`, set **`NOTIFY_MAILBOX_WINID`** or **`WINID_SCRIPT`**.

```bash
NOTIFY_MAILBOX_WINID="$HOME/embitious/tools/winid" swift run NotifyPanel
```

Override the port:

```bash
NOTIFY_MAILBOX_PORT=9000 swift run NotifyPanel
```

**List cap** (default 500, max 5000):

```bash
NOTIFY_MAILBOX_MAX=1000 swift run NotifyPanel
```

## macOS system notifications

Each successful `POST /api/notify` can also post a **banner** with the same title, body, and source as the subtitle.

- **`swift run`** (bare executable under `.build/.../debug/`): uses **`osascript display notification`**. No notification permission sheet; relies on macOS allowing scripts to post banners (usually yes for local Terminal runs).
- **Packaged `.app`**: uses **User Notifications** (`UNUserNotificationCenter`), including the permission prompt on first run.

To disable banners (app window only):

```bash
NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY=1 swift run NotifyPanel
```

## Optional auth

If `NOTIFY_MAILBOX_SECRET` is set, these require `Authorization: Bearer <secret>` or `?token=`:

- `POST /api/notify`
- `DELETE /api/notifications`
- WebSocket `GET /api/ws` (use `ws://127.0.0.1:3847/api/ws?token=…`)

Use `?token=` in the URL when opening a custom web client: `http://127.0.0.1:3847/?token=YOUR_SECRET`

`GET /api/notifications` and `GET /api/health` stay **unauthenticated** (localhost-only).

## API

### POST `/api/notify`

JSON body:

| Field    | Required | Description                    |
|----------|----------|--------------------------------|
| `title`  | no       | Default: `Notification`        |
| `body`   | no*      | `message` / `text` accepted   |
| `source` | no       | Optional tag (shown in the list if useful); omit or use a meaningful label |
| `action` | no       | **`winid open`** target id (e.g. Claude hook **`session_id`**) |
| `session_id` | no   | Same as **`action`** if `action` is omitted (mirrors Claude hook JSON). |
| `sessionId` | no    | camelCase alias for **`session_id`**. |

\* If all body fields are empty, body becomes `(no message)`.

```bash
curl -sS -X POST http://127.0.0.1:3847/api/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Claude Code","body":"Task completed"}'

# With Claude session id (same id SessionStart registered with winid):
curl -sS -X POST http://127.0.0.1:3847/api/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Done","body":"Task completed","action":"<session_id>"}'
```

### GET `/api/notifications`

`{ "notifications": [ ... ] }` (newest first).

### DELETE `/api/notifications`

Clears stored notifications (requires auth if secret is set).

### GET `/api/health`

`{ "ok": true, "items": <count> }`

### WebSocket `/api/ws`

First message: `{"type":"ready","count":n}`. Then `{"type":"notice",...}` for each new notification, or `{"type":"clear"}` when the list is cleared.

## Implementation notes

- **In-memory** only; quitting the app clears the list.
- Depends on **[FlyingFox](https://github.com/swhitty/FlyingFox)** for the HTTP/WebSocket stack.
- The previous Node.js version was replaced by this Swift package.
