# Agent Monitor (AGM)

**Agent Monitor** is a central dashboard that aggregates and controls your AI agent flows running across different Terminal tabs.

When you have multiple agents (like **Claude Code** or **Cursor Agent**) working on various tasks at the same time, it's easy to lose track of which tab is doing what. Agent Monitor solves this by pulling all their updates into one unified macOS window.

Instead of hunting through terminal tabs, you can just glance at the Monitor to see what's done, and click any task to instantly jump to the exact Terminal tab where that agent is running.

---
*Under the hood:* It's a lightweight macOS app (`agm`) that listens for events from your agents and uses `winid` to manage window focus seamlessly.

## Quick Links
- [`overview.md`](overview.md) — How it works and UI features.
- [`pty-launcher-guide.md`](pty-launcher-guide.md) — Future architecture concepts.

---

## Setup

1. Run the setup script from this directory:
   ```bash
   bash scripts/setup-notify-panel.sh
   ```
2. Start the Agent Monitor:
   ```bash
   swift run agm
   ```

*(The app window will open, and a local server will listen on port **3847**).*

---

## Hooking up your Agents

To make your agents talk to the Monitor, you just need to configure their hooks.

### 1. Claude Code
Claude Code sends JSON on `stdin` for every event. Update your `~/.claude/settings.json` to include these hooks (replace `/Users/you/...` with your actual path to this repo):

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

### 2. Cursor Agent
Run this script to globally install the hooks so Cursor can talk to the Monitor from any project:
```bash
bash scripts/install-cursor-notify-hooks.sh
```
*(Restart Cursor afterwards to load the new hooks).*

If every completion shows **twice** in the Monitor, Cursor is probably running **two** `stop` hooks (for example both `~/.cursor/hooks.json` and this repo’s `.cursor/hooks.json`). Remove the duplicate: either rely on the global install and clear the workspace `hooks.json` `stop` entry, or keep only the project file and remove the overlapping lines from `~/.cursor/hooks.json`.

---

## API & Advanced Usage

If you want to send custom notifications (e.g., from your own scripts), you can just POST to the local server.

```bash
curl -sS -X POST http://127.0.0.1:3847/api/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"My Script","body":"Finished building!","action":"<target_terminal_id>"}'
```

| Route | What it does |
|-------|--------------|
| `POST /api/notify` | Send a new notification to the dashboard. |
| `GET /api/notifications` | View the list of all notifications. |
| `DELETE /api/notifications` | Clear the dashboard. |
| `GET /api/ws` | A WebSocket stream for live custom dashboards. |

*(Note: The Monitor stores data in-memory only. Quitting the app clears the list).*
