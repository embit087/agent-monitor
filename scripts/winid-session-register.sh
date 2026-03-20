#!/usr/bin/env bash
# SessionStart hook (Claude Code or Cursor CLI): winid save <id>
# Pairs with notify-post.sh on agent turn / stop: same id is POSTed as action → winid open works.
#
# Put the Terminal / window that runs the agent in the foreground when the session starts so
# winid captures the right window.
#
# stdin: hook JSON — uses session_id (Claude Code), else conversation_id (Cursor), else sessionId.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_WINID="$TOOLS_DIR/winid"
STORE_DIR="$HOME/.winids"

winid_exe() {
  if [[ -n "${WINID_SCRIPT:-}" && -x "$WINID_SCRIPT" ]]; then
    echo "$WINID_SCRIPT"
    return 0
  fi
  if command -v winid &>/dev/null; then
    command -v winid
    return 0
  fi
  if [[ -x "$DEFAULT_WINID" ]]; then
    echo "$DEFAULT_WINID"
    return 0
  fi
  return 1
}

front_terminal_tty() {
  osascript -e '
    tell application "Terminal"
      if not (exists window 1) then return ""
      try
        return (tty of selected tab of front window) as string
      on error
        return ""
      end try
    end tell
  ' 2>/dev/null | tr -d '\r\n'
}

HOOK_JSON="$(cat)"
SID="$(printf '%s' "$HOOK_JSON" | python3 -c '
import json, sys

def pick_id(j):
    for key in ("session_id", "conversation_id", "sessionId"):
        s = j.get(key)
        if s is None:
            continue
        s = str(s).strip()
        if s:
            return s
    return ""

try:
    j = json.load(sys.stdin)
    print(pick_id(j), end="")
except Exception:
    pass
' 2>/dev/null)" || SID=""

[[ -z "$SID" ]] && exit 0
exe="$(winid_exe)" || exit 0
"$exe" save "$SID"

file="$STORE_DIR/$SID"
if [[ -f "$file" ]] && ! grep -q '^tty=' "$file" 2>/dev/null; then
  selected_tty="$(front_terminal_tty)"
  if [[ -n "$selected_tty" ]]; then
    echo "tty=$selected_tty" >> "$file"
  fi
fi
