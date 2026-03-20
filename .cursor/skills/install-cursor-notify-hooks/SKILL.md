---
name: install-cursor-notify-hooks
description: Installs Notify Panel Cursor hooks into ~/.cursor/hooks.json so sessionStart and stop fire when using Cursor Agent/CLI from any terminal or workspace. Use when hook-based notifications never fire from CLI, stop hook not running, hooks only work in one project, or they want Cursor to set up notify-panel hooks automatically.
---

# Install Notify Panel Cursor hooks (global)

## Why

Project `.cursor/hooks.json` only loads when **that repo** is the workspace root. Cursor CLI started from another terminal often uses a **different** root, so **`stop` never runs**.

**Fix:** merge hooks into **user** config: `~/.cursor/hooks.json` with **absolute** paths to this package’s scripts.

## What to run

From the **notify-panel** Swift package directory (`tools/agent-monitor` in the monorepo — the folder that contains `scripts/install-cursor-notify-hooks.sh`):

```bash
bash scripts/install-cursor-notify-hooks.sh
```

If the agent does not know the path: search the workspace or user tree for `install-cursor-notify-hooks.sh`, `cd` to its parent directory (repo/package root), then run the command above.

## After install

1. **Restart** Cursor or start a **new** agent/CLI session so hooks reload.
2. Keep **Notify Panel** running (`swift run NotifyPanel` or the app) so `POST /api/notify` succeeds.
3. **Trust** still applies to project policies; user hooks should run regardless of workspace.

## Re-run when

- This folder was **moved** or **cloned** elsewhere (paths in `hooks.json` must stay valid).
- Hooks were removed from `~/.cursor/hooks.json` by mistake.

## Optional

To **remove** only these hooks from `hooks.json`, edit the file and delete array elements whose `command` contains `winid-session-register.sh` or `cursor-stop-notify.sh` (or legacy `mailbox-winid-register.sh` / `cursor-stop-mailbox.sh`).
