# Winid Feature - Overview & Setup

## What is Winid?

**Winid** is a window-switching system that lets you instantly jump to Terminal tabs running specific agents. When you click on a notification in Agent Monitor, it uses winid to:

1. Look up the saved window/tab ID (stored during agent startup)
2. Find that Terminal tab by its unique TTY or title
3. Raise and focus that specific tab

This eliminates tab-hunting — you always have the right terminal in focus when an agent finishes.

## How It Works

### Three Components

```
┌─────────────────────────────────────────────────────────┐
│ Agent Execution (Claude Code, Cursor, etc.)             │
│  ↓ (on session start)                                    │
│  └─→ winid-session-register.sh (hook)                   │
│       └─→ winid save <session_id>                        │
│           (saves Terminal tab info to ~/.winids/)        │
│  ↓ (on task completion)                                  │
│  └─→ notify-post.sh                                      │
│       └─→ POST to Agent Monitor HTTP server              │
│  ↓                                                        │
│                                                           │
├─────────────────────────────────────────────────────────┤
│ Agent Monitor App (macOS / SwiftUI)                      │
│  ↓ (receives notification with session_id)              │
│  └─→ PanelModel.openWinidSession(id)                    │
│       └─→ WinidTerminalRunner.openSession()             │
│            └─→ Runs: winid open <session_id>            │
│                (via /bin/bash -lc command)              │
│                                                           │
├─────────────────────────────────────────────────────────┤
│ Winid Script (~/.agm/bin/winid)                         │
│  ↓ (performs AppleScript magic)                          │
│  └─→ Uses Terminal.app's AppleScript interface          │
│       to find and focus the saved tab                    │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### The Winid Script Itself

**Location:** `/Users/objsinc-macair-00/embitious/tools/winid` (source)
**Installed to:** `~/.agm/bin/winid` (where Agent Monitor looks for it)

The script provides these commands:

| Command | Purpose |
|---------|---------|
| `winid save <id>` | Capture the current frontmost Terminal tab with an identifier |
| `winid open <id>` | Focus a saved Terminal tab |
| `winid send <id> <text>` | Send text/command to a saved Terminal session |
| `winid list` | Show all saved window IDs |
| `winid remove <id>` | Forget a saved window ID |
| `winid clear-all` | Remove all saved IDs |
| `winid current` | Show info about the current frontmost window |
| `winid session` | Print WINID_SESSION_UUID for this shell |

### Key Implementation Details

**Storage:** Saved window metadata is stored in files under `~/.winids/`:
```bash
$ cat ~/.winids/eadaf7b1-7a29-4b99-9832-70156380c48a
app_name=Terminal
bundle_id=com.apple.Terminal
win_name=...
saved_at=2026-03-21 09:07:14
tty=/dev/ttys012
```

**Terminal Identification:** The script uses two strategies:
1. **TTY-based** (most reliable): If the Terminal tab's `/dev/ttyXXX` is saved, winid finds the exact tab
2. **Title-based** (fallback): If the TTY changes or the tab is recreated, matches by window/tab title

**AppleScript Magic:** The focusing is done via macOS Terminal.app's AppleScript API:
```applescript
tell application "Terminal"
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t is "/dev/ttys012" then
                set index of w to 1
                set selected tab of w to t
                return "found"
            end if
        end repeat
    end repeat
end tell
```

## Installation & Setup

### Critical: Install Winid to Standard Location

The Agent Monitor app searches for `winid` in this order:
1. `NOTIFY_MAILBOX_WINID` environment variable
2. `WINID_SCRIPT` environment variable
3. **`~/.agm/bin/winid`** ← **INSTALL HERE**
4. `~/.local/bin/winid`
5. `/usr/local/bin/winid`
6. Repo-adjacent fallback (broken when app is compiled)

**One-time setup:**
```bash
mkdir -p ~/.agm/bin
cp /Users/objsinc-macair-00/embitious/tools/winid ~/.agm/bin/winid
chmod +x ~/.agm/bin/winid
```

Verify installation:
```bash
~/.agm/bin/winid current
```

### Enable Hooks

Winid only works if the agent hooks are set up. These scripts call `winid save` when agents start:

- **Claude Code:** Hook script `scripts/claude-sessionstart-notify.sh` must be configured in Claude Code settings
- **Cursor Agent:** Similar hook registration via `scripts/setup-notify-panel.sh`

Without these hooks, window IDs are never saved, so winid has nothing to focus.

## Troubleshooting

### Issue: "Clicking notifications doesn't switch terminals"

**Diagnosis:**
```bash
# 1. Check if winid is findable
ls -l ~/.agm/bin/winid

# 2. Check if any windows are saved
winid list

# 3. Try opening a window manually
winid open <any-id-from-list>
```

**If winid is not found:**
- Re-run installation step above

**If winid is found but no windows are saved:**
- Hooks are not running. Check Agent Monitor logs: `log stream --predicate 'process == "Agent Monitor"'`
- Verify hook is registered in Claude Code settings (should be `scripts/claude-sessionstart-notify.sh`)

**If winid open fails with "Warning: Could not find Terminal":**
- The Terminal tab may have been closed or TTY reused
- Try `winid save <id>` again from that tab
- Or use `winid remove <id>` and let a new agent session create a fresh entry

### Issue: TTY Detection Shows "not a tty"

When saving a window from a non-interactive context (e.g., from the Agent Monitor app itself calling `winid current`), the TTY detection may fail. This is expected and doesn't affect functionality — the script falls back to title-based matching.

### Debug Mode

```bash
# See exactly what the script sees
winid current

# List all saved windows with verbose output
winid list
```

## Reliability Improvements Made

### ✓ Installation to Standard Location
The critical fix applied ensures the app can locate winid in `~/.agm/bin/winid` even when running as a compiled macOS application.

### ✓ Fallback Strategies
The winid script includes two fallback strategies:
1. TTY-based focusing (most reliable)
2. Title-based matching (if TTY changes)
3. Both strategies are used to maximize chances of finding the target tab

### ✓ Debouncing
PanelModel.swift debounces switch requests — ignores rapid-fire duplicate requests within 1 second to prevent race conditions.

### ✓ Status Feedback
The app shows real-time feedback:
- `.switching(id)` while executing
- `.succeeded(id)` on success (auto-clears after 3s)
- `.failed(msg)` on error (auto-clears after 5s)

## Future Improvements

### Potential Enhancements
1. **Add to PATH:** Make `winid` globally available: `ln -s ~/.agm/bin/winid /usr/local/bin/winid`
2. **Launchd Integration:** Auto-register window IDs on Terminal tab creation (would reduce hook dependency)
3. **Historical Tracking:** Log which terminals have been opened and when
4. **Smart Matching:** Improve title-based matching for edge cases (multiple windows with same base title)

## Files Involved

| File | Purpose |
|------|---------|
| `/Users/objsinc-macair-00/embitious/tools/winid` | Source script |
| `~/.agm/bin/winid` | Installed executable (must exist) |
| `~/.winids/` | Directory storing window metadata files |
| `Sources/agm/WinidLocator.swift` | Locates the winid script (searches known locations) |
| `Sources/agm/WinidTerminalRunner.swift` | Executes `winid open` commands |
| `scripts/winid-session-register.sh` | Claude Code hook — calls `winid save` |
| `PanelModel.swift` | Calls openWinidSession when user clicks notification |

## Testing Checklist

- [ ] `~/.agm/bin/winid` exists and is executable
- [ ] `winid list` shows saved window IDs
- [ ] `winid open <id>` successfully focuses a Terminal tab
- [ ] Agent Monitor app shows "Focusing Terminal..." message
- [ ] Clicking a notification in Agent Monitor switches the terminal
- [ ] No errors in Console.app for Agent Monitor process
- [ ] Winid gracefully handles missing tabs (exit code 2, shows warning)
