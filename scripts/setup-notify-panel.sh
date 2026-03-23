#!/usr/bin/env bash
# DEPRECATED: Use `bash install.sh` instead for a complete one-click install.
# This script is kept for backward compatibility with existing workflows.
#
# One-shot setup: executable bits, Cursor ~/.cursor/hooks.json, swift build, sanity checks, next steps.
#
# Usage:
#   bash scripts/setup-notify-panel.sh
#   bash scripts/setup-notify-panel.sh --no-build    # skip swift build
#   bash scripts/setup-notify-panel.sh --no-cursor   # skip hooks installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$(cd "$REPO_ROOT/.." && pwd)"

DO_BUILD=1
DO_CURSOR=1
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --no-cursor) DO_CURSOR=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-build] [--no-cursor]"
      exit 0
      ;;
  esac
done

echo "==> Notify Panel setup (repo: $REPO_ROOT)"
echo

echo "==> chmod +x hook scripts"
chmod +x \
  "$SCRIPT_DIR/notify-post.sh" \
  "$SCRIPT_DIR/winid-session-register.sh" \
  "$SCRIPT_DIR/install-cursor-notify-hooks.sh" \
  "$SCRIPT_DIR/claude-stop-notify.sh" \
  "$SCRIPT_DIR/claude-sessionstart-notify.sh" \
  "$SCRIPT_DIR/setup-notify-panel.sh" \
  "$REPO_ROOT/.cursor/hooks/cursor-stop-notify.sh" \
  2>/dev/null || true

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]] && grep -qE 'claude-(stop|sessionstart)-mailbox\.sh' "$CLAUDE_SETTINGS" 2>/dev/null; then
  echo
  echo "==> Migrate ~/.claude/settings.json (claude-*-mailbox.sh → claude-*-notify.sh)"
  perl -0777 -i -pe 's/claude-stop-mailbox\.sh/claude-stop-notify.sh/g; s/claude-sessionstart-mailbox\.sh/claude-sessionstart-notify.sh/g' "$CLAUDE_SETTINGS"
fi

if [[ "$DO_CURSOR" -eq 1 ]]; then
  echo
  echo "==> Install Cursor user hooks (~/.cursor/hooks.json)"
  bash "$SCRIPT_DIR/install-cursor-notify-hooks.sh"
else
  echo
  echo "==> Skipped Cursor hooks (--no-cursor)"
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
  echo
  echo "==> swift build"
  (cd "$REPO_ROOT" && swift build)
else
  echo
  echo "==> Skipped swift build (--no-build)"
fi

winid_path=""
if [[ -n "${NOTIFY_MAILBOX_WINID:-}" && -x "${NOTIFY_MAILBOX_WINID}" ]]; then
  winid_path="$NOTIFY_MAILBOX_WINID"
elif [[ -n "${WINID_SCRIPT:-}" && -x "${WINID_SCRIPT}" ]]; then
  winid_path="$WINID_SCRIPT"
elif [[ -x "$HOME/embitious/tools/winid" ]]; then
  winid_path="$HOME/embitious/tools/winid"
elif [[ -x "$HOME/tools/winid" ]]; then
  winid_path="$HOME/tools/winid"
elif [[ -x "$TOOLS_DIR/winid" ]]; then
  winid_path="$TOOLS_DIR/winid"
elif command -v winid &>/dev/null; then
  winid_path="$(command -v winid)"
fi

echo
if [[ -n "$winid_path" ]]; then
  echo "==> winid: OK ($winid_path)"
else
  echo "==> winid: not found (set NOTIFY_MAILBOX_WINID or WINID_SCRIPT, or install tools/winid)" >&2
fi

REG_SH="$SCRIPT_DIR/winid-session-register.sh"
POST_SH="$SCRIPT_DIR/notify-post.sh"

echo
cat <<EOF
────────────────────────────────────────────────────────────
Next steps
────────────────────────────────────────────────────────────

1. Restart Cursor (or start a new Agent session) so hooks reload.

2. Run Notify Panel when you want to receive hook events:
     cd "$REPO_ROOT"
     swift run NotifyPanel

3. Claude Code — add command hooks in ~/.claude/settings.json (see README.md for full JSON).
   SessionStart command (winid save):
     $REG_SH
   Stop command (POST to Notify Panel):
     $POST_SH "Claude Code" "Turn complete"

   Cursor/Claude hybrid wrappers (ignore Cursor stdin when imported):
     $SCRIPT_DIR/claude-sessionstart-notify.sh
     $SCRIPT_DIR/claude-stop-notify.sh

────────────────────────────────────────────────────────────
EOF
