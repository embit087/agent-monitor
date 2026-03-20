# Notify Panel — System Overview

A macOS-native notification aggregation system that surfaces Claude Code session completions in a unified panel and enables one-click terminal switching. Built as a Swift/SwiftUI application with an embedded HTTP server, integrated with Claude Code hooks, the `winid` window-management tool, and Fish shell session tracking.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Component Map](#component-map)
3. [Lifecycle Flow](#lifecycle-flow)
4. [The `winid` Tool](#the-winid-tool)
5. [Fish Shell Integration](#fish-shell-integration)
6. [Claude Code Hook Configuration](#claude-code-hook-configuration)
7. [The Swift Application](#the-swift-application)
8. [Supplementary Tools](#supplementary-tools)
9. [API Reference](#api-reference)
10. [Environment Variables](#environment-variables)
11. [One-Click Installation Vision](#one-click-installation-vision)
12. [File Inventory](#file-inventory)

---

## Architecture

```
                             macOS
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  Terminal.app                                            │
  │  ┌────────────────────┐  ┌────────────────────┐         │
  │  │ Tab 1: Claude Code │  │ Tab 2: Claude Code │  ...    │
  │  │ (session A)        │  │ (session B)        │         │
  │  └────────┬───────────┘  └────────┬───────────┘         │
  │           │ SessionStart hook      │ Stop hook           │
  │           │                        │                     │
  │           ▼                        ▼                     │
  │  ┌─────────────────┐    ┌────────────────────────┐      │
  │  │ winid save <id> │    │ curl POST /api/notify  │      │
  │  │ (~/.winids/<id>) │    │ { action: session_id } │      │
  │  └─────────────────┘    └───────────┬────────────┘      │
  │                                     │                    │
  │                                     ▼                    │
  │                    ┌─────────────────────────────┐       │
  │                    │  Notify Panel app   │       │
  │                    │  (SwiftUI + FlyingFox HTTP) │       │
  │                    │  127.0.0.1:3847             │       │
  │                    │                             │       │
  │                    │  ┌──────────────────────┐   │       │
  │                    │  │ 12                   │   │       │
  │                    │  │ ┌──────────────────┐ │   │       │
  │                    │  │ │ Claude Code      │ │   │       │
  │                    │  │ │ Task completed   │ │   │       │
  │                    │  │ │ [Session tabs…]  │   │       │
  │                    │  │ └──────────────────┘ │   │  │    │
  │                    │  └──────────────────────┘   │  │    │
  │                    └─────────────────────────────┘  │    │
  │                                                     │    │
  │                     ┌───────────────────────────────┘    │
  │                     ▼                                    │
  │            winid open <session_id>                       │
  │            → AppleScript focuses the saved Terminal tab  │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

The system solves a specific workflow problem: when running multiple Claude Code sessions across Terminal tabs, the user needs to know when each session's turn completes and quickly switch to the right tab. Rather than watching each tab, Notify Panel collects completion events in one place and provides a **Switch agent** control that focuses the exact Terminal tab via AppleScript.

---

## Component Map

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| **Notify Panel** | Swift/SwiftUI app | `tools/agent-monitor/` | Local notification list + HTTP server |
| **winid** | Bash script | `tools/winid` | Save/restore macOS windows by ID |
| **99-winid-session.fish** | Fish conf.d snippet | `tools/fish/conf.d/99-winid-session.fish` | Auto-register Fish sessions with winid |
| **notify-post.sh** | Bash hook script | `tools/agent-monitor/scripts/notify-post.sh` | Claude Code Stop hook — POST to Notify Panel |
| **winid-session-register.sh** | Bash hook script | `tools/agent-monitor/scripts/winid-session-register.sh` | Claude Code SessionStart hook — winid save |
| **cc-notify** | Bash script | `tools/cc-notify` | Alternative Stop hook — macOS banner via terminal-notifier |
| **cc-focus** | Bash script | `tools/cc-focus` | Click handler for cc-notify — `winid open cc` |
| **settings.json** | Claude Code config | `~/.claude/settings.json` | Hook wiring for SessionStart, Stop, UserPromptSubmit |

---

## Lifecycle Flow

### 1. Shell Session Initialization (Fish)

When a new interactive Fish shell starts:

```
Fish starts
  → 99-winid-session.fish loads (conf.d)
  → Generates WINID_SESSION_UUID via uuidgen
  → Calls `winid save $WINID_SESSION_UUID`
  → Stores frontmost Terminal window metadata in ~/.winids/<uuid>
  → Prints: WINID_SESSION_UUID=<uuid>
```

This pre-registers every Terminal tab so that `winid open <uuid>` can focus it later.

### 2. Claude Code SessionStart

When Claude Code launches in a Terminal tab, the `SessionStart` hook fires:

```
Claude Code starts
  → settings.json SessionStart hook executes:
      SESSION=$(winid session)    # reads WINID_SESSION_UUID from env
      winid save $SESSION         # captures frontmost window → ~/.winids/<session_id>
  → The Terminal tab is now registered under the Claude Code session's winid UUID
```

The `winid-session-register.sh` script (an alternative/package-local implementation) does the same but reads `session_id` from the hook's stdin JSON:

```
Claude Code starts
  → Hook pipes JSON to stdin: { "session_id": "abc-123-..." }
  → winid-session-register.sh:
      Extracts session_id from JSON via python3
      Calls: winid save <session_id>
      Appends TTY to ~/.winids/<session_id> if missing
```

### 3. Claude Code Turn Completion (Stop Hook)

When Claude Code finishes a turn, two Stop hooks fire in parallel:

**Hook 1 — Panel notification (inline curl):**
```
Claude Code turn completes
  → Stop hook executes:
      SESSION=$(winid session)
      curl POST http://127.0.0.1:3847/api/notify
        { "title": "Claude Code",
          "body": "Task completed",
          "source": "Stop",
          "action": "$SESSION" }    # session_id enables "Switch agent"
```

**Hook 2 — macOS banner notification (cc-notify):**
```
Claude Code turn completes
  → cc-notify executes:
      Double-forks terminal-notifier
      → macOS banner: "Claude Code — Task completed — click to switch"
      → On click: executes cc-focus → winid open cc
```

### 4. User Interaction — Switch agent

When the user chooses a session in the **horizontal agent tab strip** or clicks an actionable notification card:

```
User clicks a session tab or a mint-bordered notification card
  → ContentView calls model.openWinidSession(sessionId)
  → WinidTerminalRunner.openSession(sessionId:winidPath:)
  → Spawns: /bin/bash -lc "winid open '<session_id>'"
  → winid reads ~/.winids/<session_id>
  → Finds saved TTY (e.g., /dev/ttys005)
  → AppleScript: iterate Terminal windows/tabs, match TTY, raise window
  → macOS brings the correct Terminal tab to the foreground
  → User continues the session by typing in Terminal (no in-app send box)
```

---

## The `winid` Tool

**Path:** `tools/winid` (342 lines, Bash)

A standalone window identity manager for macOS. It stores window metadata in `~/.winids/` and uses AppleScript to focus previously saved windows.

### Commands

| Command | Description |
|---------|-------------|
| `winid save <id>` | Capture frontmost window (app, bundle ID, title, TTY) → `~/.winids/<id>` |
| `winid open <id>` | Focus a previously saved window using stored metadata |
| `winid list` | List all saved window IDs with app name and identifier |
| `winid remove <id>` | Delete a saved window record |
| `winid clear-all` | Delete all saved window records |
| `winid current` | Print info about the current frontmost window |
| `winid session` | Print `WINID_SESSION_UUID` from the environment |

### Window Record Format (`~/.winids/<id>`)

```
app_name=Terminal
bundle_id=com.apple.Terminal
win_name=fish — 120×35
saved_at=2026-03-20 14:30:00
tty=/dev/ttys005
```

### Focus Strategy

For Terminal windows, `winid open` uses a layered matching approach:

1. **TTY-based focus** (most reliable): iterates all Terminal windows/tabs, matches the stored `tty` field via AppleScript
2. **Title-based fallback**: if the TTY is gone (tab restarted), builds title candidates by stripping the transient dimension suffix (e.g., `120x35`) and matches against window names and custom tab titles
3. **Generic app focus**: for non-Terminal windows, activates the app and uses `AXRaise` on the matching window

### Design Choices

- **Safe reader**: uses `grep` + `cut` to read stored fields — no `source` or `eval` to avoid injection
- **Python helper**: `build_terminal_title_candidates` generates fuzzy title variants to handle Terminal's dynamic title changes
- **AppleScript core**: all window focusing uses AppleScript via `osascript`, the only reliable way to manipulate macOS window ordering

---

## Fish Shell Integration

**Path:** `tools/fish/conf.d/99-winid-session.fish`

**Installation:** `ln -sf /path/to/tools/fish/conf.d/99-winid-session.fish ~/.config/fish/conf.d/`

This conf.d snippet provides two things:

### 1. Global `winid` Function

Wraps the `winid` bash script as a Fish function with automatic path discovery:

```
Resolution order:
  1. $WINID_SCRIPT environment variable
  2. ~/embitious/tools/winid (hardcoded default)
  3. Relative path from this config file's location (tools/../winid)
```

### 2. Per-Session UUID Registration

On every new interactive Fish shell:

1. Generates `WINID_SESSION_UUID` via `uuidgen` (fallback: Python `uuid.uuid4()`, then timestamp format)
2. Exports it as a global variable (`set -gx`)
3. Calls `winid save $WINID_SESSION_UUID` to register the Terminal window
4. Skips registration for SSH sessions (no local window to save)

This means every Terminal tab automatically has a unique UUID that maps to its window. Claude Code inherits this UUID in its environment, and the Stop hook uses it to tag notifications so Notify Panel knows which tab to focus.

---

## Claude Code Hook Configuration

**Path:** `~/.claude/settings.json`

The hooks section wires Claude Code lifecycle events to the notification system:

### SessionStart Hook

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "SESSION=$(/path/to/winid session); /path/to/winid save $SESSION"
    }
  ]
}
```

Captures the Terminal window under the current `WINID_SESSION_UUID` when a Claude Code session begins. This ensures `winid open` can later focus this exact tab.

### Stop Hook (Notify Panel)

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "SESSION=$(/path/to/winid session); curl -sS --max-time 2 -X POST http://127.0.0.1:3847/api/notify -H 'Content-Type: application/json' -d \"{\\\"title\\\":\\\"Claude Code\\\",\\\"body\\\":\\\"Task completed\\\",\\\"source\\\":\\\"Stop\\\",\\\"action\\\":\\\"$SESSION\\\"}\" || true"
    }
  ]
}
```

POSTs a notification to Notify Panel with the session UUID as the `action` field. The `|| true` ensures the hook never fails Claude Code even if Notify Panel isn't running. `--max-time 2` prevents blocking if the server is unresponsive.

### Stop Hook (cc-notify — macOS Banner)

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "/path/to/cc-notify"
    }
  ]
}
```

Sends a native macOS notification banner via `terminal-notifier`. Clicking the banner executes `cc-focus`, which runs `winid open cc`.

### UserPromptSubmit Hook (cc-n Shortcut)

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "cat - | grep -q 'cc-n' && { SESSION=$(winid session); echo -n \"$SESSION\" | pbcopy; osascript -e \"display notification ...\"; } || true"
    }
  ]
}
```

When the user types `cc-n` in a prompt, copies the current session UUID to the clipboard and shows a notification. Useful for manually referencing the session ID.

---

## The Swift Application

### Technology Stack

- **Swift 5.10+** / **macOS 14+**
- **SwiftUI** for the window UI
- **FlyingFox 0.26+** for the embedded HTTP/WebSocket server
- **Swift Concurrency** (async/await, actors, Task.detached)

### Source Files

#### `NotifyPanelApp.swift` (Entry Point)
The `@main` struct creates a `WindowGroup` with `ContentView`, initializes `SystemNotificationSupport`, and starts the HTTP server on appearance. Window size defaults to 560x640. The "New Window" menu item is disabled.

#### `PanelModel.swift` (State Management)
The `@MainActor` observable object holds:
- `items: [Notice]` — notification list (newest first, capped at `maxItems`)
- `serverRunning: Bool` — server status for the UI pill indicator
- `port: UInt16` — from `NOTIFY_MAILBOX_PORT` or `PORT` (default 3847)
- `maxItems: Int` — from `NOTIFY_MAILBOX_MAX` (default 500, max 5000)
- `secret: String?` — from `NOTIFY_MAILBOX_SECRET`
- `winidExecutableURL: URL?` — resolved `winid` path via `WinidLocator`
- `hub: BrowserHub` — WebSocket broadcast controller

Key methods:
- `startServerIfNeeded()` — launches the server in a Task
- `applyAppend(_ notice:)` — adds notification, trims overflow, posts system notification
- `openWinidSession(_ sessionId:)` — delegates to `WinidTerminalRunner`
- `clearListFromUI()` — empties the list and broadcasts `{"type":"clear"}` to WebSocket clients

#### `LocalHTTPServer.swift` (HTTP/WebSocket Server)
Uses FlyingFox bound to IPv4 loopback (`127.0.0.1`, not `localhost` / `::1`). Routes:

| Route | Auth | Description |
|-------|------|-------------|
| `POST /api/notify` | Yes (if secret set) | Create notification |
| `GET /api/notifications` | No | List all notifications |
| `DELETE /api/notifications` | Yes | Clear stored notifications |
| `GET /api/health` | No | Health check: `{"ok":true,"items":N}` |
| `GET /api/ws` | Yes | WebSocket — live updates |

Authentication: `Authorization: Bearer <secret>` header or `?token=<secret>` query param.

#### `Notice.swift` (Data Model + Codec)
The `Notice` struct: `id` (UUID), `at` (Date), `title`, `body`, `source?`, `action?`.

`NotifyPayload` accepts flexible field names:
- Body: `body`, `message`, or `text`
- Action: `action`, `session_id`, or `sessionId`

Length limits: title 200, body 8000, source 120, action 500. Missing title defaults to "Notification", missing body defaults to "(no message)".

WebSocket message format: `{"type":"notice","id":"...","at":"...","title":"...","body":"...","source":"...","action":"..."}`

#### `BrowserHub.swift` (WebSocket Fan-Out)
An actor that maintains a dictionary of subscriber callbacks. `broadcast()` sends a message to all connected WebSocket clients. Used for live list updates.

#### `WinidLocator.swift` (Executable Discovery)
Resolves the `winid` script path via a priority chain:
1. `NOTIFY_MAILBOX_WINID` env var
2. `WINID_SCRIPT` env var
3. `~/embitious/tools/winid`
4. `~/tools/winid`
5. Repo-adjacent: `../winid` relative to the package root

Returns `URL?` — `nil` if no executable found (the app still works; "Switch agent" uses login-shell `PATH`).

#### `WinidSessionId.swift` (Session ID Resolution)
Resolves the current session ID via:
1. `NOTIFY_MAILBOX_TEST_SESSION` (manual override for testing)
2. `CLAUDE_CODE_SESSION_ID` (from Claude Code environment)
3. `WINID_SESSION_UUID` (Fish shell integration)
4. `winid session` command (if executable found)

#### `WinidTerminalRunner.swift` (Terminal Focus Execution)
Runs `winid open <sessionId>` via `/bin/bash`:
- If `winidPath` is known: `bash -lc "<path> open '<id>'"` (login shell, non-interactive)
- If `winidPath` is nil: `bash -ilc "winid open '<id>'"` (interactive login shell, so winid is found on PATH)

Executed in a `Task.detached` — non-blocking, output discarded. Shell quoting handles embedded single quotes.

#### `SystemNotificationSupport.swift` (macOS Banners)
Dual notification path:
- **Packaged `.app`**: uses `UNUserNotificationCenter` (with permission prompt)
- **`swift run` (bare binary)**: uses `osascript display notification` (no permission needed)

Disabled with `NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY=1`.

#### `ContentView.swift` (UI)
SwiftUI layout:
- **Top chrome**: "Monitor Agents" title, subtitle (server status), status dot (mint = ready, orange = starting), trash icon to clear all (Cmd+Delete) with a confirmation alert before clearing
- **Filter + agent switcher** (one row below the header): Segmented control **All / Cursor / Claude Code** with each segment showing **distinct session count** for that filter (unique non-empty **`action`** values—same id as Session ID / winid target—not row count). **Cursor** keeps rows whose **title** contains “cursor” (standard localized containment). **Claude Code** keeps rows whose title contains “claude code” or compact “claudecode”. To the right, a horizontal scroll of **agent session tabs** (tinted by source: Cursor / Claude / other): one tab per **distinct normalized `action`** in the **filtered** list; each passes **`openAction`** from the **newest** notice for that session. **`winid open`** runs after a **short async delay** so AppKit can finish click handling before Terminal focus (see `WinidTerminalRunner.openSession`).
- **Inbox section**: scrollable `LazyVStack`
- **Notice rows**: title, timestamp, source badge (hidden for "Stop"), session ID (monospaced, selectable), optional `request` copy, main body/summary mint-outlined block. If a row has an `action`, the **whole card is clickable** and gets a **solid mint border** so it acts as the switch-agent trigger.
- **Empty state**: tray icon, hint about POST /api/notify and winid configuration
- **Background**: window color with subtle mint gradient overlay

---

## Supplementary Tools

### `cc-notify` (`tools/cc-notify`)

A Stop hook alternative that uses `terminal-notifier` (Homebrew) for native macOS notification banners. Double-forks to fully detach from the hook process tree, allowing the notification to persist and handle click callbacks after the hook shell exits.

```bash
#!/bin/bash
FOCUS_SCRIPT="/path/to/cc-focus"
(
  (
    terminal-notifier \
      -title 'Claude Code' \
      -message 'Task completed — click to switch' \
      -sound default \
      -sender com.apple.Terminal \
      -execute "$FOCUS_SCRIPT"
  ) </dev/null >/dev/null 2>&1 &
) &
```

### `cc-focus` (`tools/cc-focus`)

Click handler for cc-notify. Focuses a pre-registered window named "cc":

```bash
#!/bin/bash
winid open cc
```

This provides a simpler (non-session-aware) focus model: all Claude Code terminals share one fixed window ID "cc". Notify Panel's per-session model is more granular.

---

## API Reference

### `POST /api/notify`

Create a notification.

**Request body (JSON):**

| Field | Required | Description |
|-------|----------|-------------|
| `title` | No | Notification title (default: "Notification", max 200 chars) |
| `body` / `message` / `text` | No | Body text (default: "(no message)", max 8000 chars) |
| `source` | No | Origin label (max 120 chars); "Stop" is hidden in the UI |
| `action` / `session_id` / `sessionId` | No | `winid open` target — the session UUID |

**Response:** `201 Created` with the Notice JSON.

**Example:**
```bash
curl -sS -X POST http://127.0.0.1:3847/api/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Claude Code","body":"Task completed","action":"abc-123"}'
```

### `GET /api/notifications`

Returns `{"notifications":[...]}` (newest first). Unauthenticated.

### `DELETE /api/notifications`

Clears stored notifications. Requires auth if `NOTIFY_MAILBOX_SECRET` is set.

### `GET /api/health`

Returns `{"ok":true,"items":<count>}`. Unauthenticated.

### `GET /api/ws`

WebSocket endpoint. Messages:
- On connect: `{"type":"ready","count":N}`
- On new notification: `{"type":"notice","id":"...","at":"...","title":"...","body":"...","source":"...","action":"..."}`
- On clear: `{"type":"clear"}`

Connect with auth: `ws://127.0.0.1:3847/api/ws?token=YOUR_SECRET`

---

## Environment Variables

### Notify Panel application

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFY_MAILBOX_PORT` | `3847` | HTTP server port |
| `PORT` | — | Alternative port (lower priority than `NOTIFY_MAILBOX_PORT`) |
| `NOTIFY_MAILBOX_MAX` | `500` | Max items retained (range: 1–5000) |
| `NOTIFY_MAILBOX_SECRET` | — | Bearer token for POST/DELETE/WS auth |
| `NOTIFY_MAILBOX_NO_SYSTEM_NOTIFY` | — | Set to `1` to disable macOS banners |
| `NOTIFY_MAILBOX_WINID` | — | Explicit path to `winid` script |

### Hook Scripts

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFY_MAILBOX_PORT` | `3847` | Server port for curl target |
| `NOTIFY_MAILBOX_URL` | `http://127.0.0.1:<PORT>` | Full base URL override |
| `NOTIFY_MAILBOX_SECRET` | — | Bearer token for POST auth |
| `WINID_SCRIPT` | — | Explicit `winid` path for shell scripts |
| `MAILBOX_PREFER_WINID` | — | Set to `1` to force Fish/winid UUID over Claude `session_id` |

### Session Resolution

| Variable | Description |
|----------|-------------|
| `WINID_SESSION_UUID` | Set by Fish shell (99-winid-session.fish) — per-tab UUID |
| `CLAUDE_CODE_SESSION_ID` | Set by Claude Code — session identifier |
| `NOTIFY_MAILBOX_TEST_SESSION` | Manual override for testing |

---

## One-Click Installation Vision

The current system requires manual setup across multiple locations. The goal is to consolidate into a single installable package:

### Current Manual Setup Steps

1. Clone the repository containing `tools/`
2. Build the Swift app: `cd agent-monitor && swift run NotifyPanel`
3. Symlink Fish config: `ln -sf .../tools/fish/conf.d/99-winid-session.fish ~/.config/fish/conf.d/`
4. Make scripts executable: `chmod +x tools/winid tools/cc-notify tools/cc-focus scripts/*.sh`
5. Install `terminal-notifier`: `brew install terminal-notifier`
6. Configure Claude Code hooks in `~/.claude/settings.json`
7. Restart Fish shell to activate `WINID_SESSION_UUID`

### Target One-Click Package

The package should:

1. **Build and install the Swift app** — either as a `.app` bundle (for UNUserNotificationCenter support) or via `swift build` with a launchd plist for auto-start
2. **Install the `winid` script** to a stable PATH location
3. **Install the Fish conf.d snippet** to `~/.config/fish/conf.d/`
4. **Register Claude Code hooks** — merge the required SessionStart and Stop hooks into `~/.claude/settings.json` (or a project-level settings file)
5. **Install dependencies** — `terminal-notifier` via Homebrew (for cc-notify)
6. **Auto-start Notify Panel** — via launchd, login items, or similar

### Implementation Approach

- A single installer script (e.g., `install.sh`) or Homebrew formula
- The Claude Code hooks would be injected into `settings.json` using a JSON merge tool, preserving existing user configuration
- The React Native application variant would be built automatically as part of the installation, providing a cross-platform notification UI
- Hook paths would use the installed locations rather than repository-relative paths

---

## File Inventory

### Core Application (`tools/agent-monitor/`)

| File | Lines | Role |
|------|-------|------|
| `Package.swift` | 24 | Swift package manifest (FlyingFox dependency, macOS 14+) |
| `Sources/NotifyPanel/NotifyPanelApp.swift` | 24 | SwiftUI entry point |
| `Sources/NotifyPanel/ContentView.swift` | 316 | Full UI: list, notice rows, empty state |
| `Sources/NotifyPanel/PanelModel.swift` | 92 | App state, environment config, server lifecycle |
| `Sources/NotifyPanel/LocalHTTPServer.swift` | 149 | FlyingFox HTTP/WebSocket server |
| `Sources/NotifyPanel/Notice.swift` | 123 | Data model, JSON codec, payload parsing |
| `Sources/NotifyPanel/BrowserHub.swift` | 24 | WebSocket broadcast actor |
| `Sources/NotifyPanel/SystemNotificationSupport.swift` | 115 | macOS banner notifications |
| `Sources/NotifyPanel/WinidLocator.swift` | 37 | winid executable discovery |
| `Sources/NotifyPanel/WinidSessionId.swift` | 42 | Session ID resolution chain |
| `Sources/NotifyPanel/WinidTerminalRunner.swift` | 43 | Terminal.app shell execution |
| `scripts/notify-post.sh` | 113 | Stop hook — POST to Notify Panel |
| `scripts/winid-session-register.sh` | 70 | SessionStart hook — winid save |
| `README.md` | 168 | Project README |

### Supporting Tools (`tools/`)

| File | Lines | Role |
|------|-------|------|
| `winid` | 342 | Window identity manager (Bash + AppleScript) |
| `cc-notify` | 19 | Stop hook — macOS banner via terminal-notifier |
| `cc-focus` | 3 | Click handler — `winid open cc` |
| `fish/conf.d/99-winid-session.fish` | 43 | Fish shell winid function + session UUID auto-registration |

### Configuration

| File | Role |
|------|------|
| `~/.claude/settings.json` | Claude Code hooks wiring (SessionStart, Stop, UserPromptSubmit) |
| `~/.winids/` | winid window metadata store (one file per saved ID) |
| `~/.config/fish/conf.d/` | Fish shell configuration (symlinked 99-winid-session.fish) |
