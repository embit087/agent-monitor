#!/usr/bin/env bash
# Claude Code StopFailure hook for Agent Monitor.
# Posts a notification when a turn ends due to error (silent — no macOS banner).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agm-env.sh"

HOOK_JSON=""
if [ ! -t 0 ]; then
  HOOK_JSON="$(cat || true)"
fi

IS_CURSOR="0"
if [[ -n "$HOOK_JSON" ]]; then
  IS_CURSOR="$(printf '%s' "$HOOK_JSON" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
    print("1" if payload.get("cursor_version") else "0", end="")
except Exception:
    print("0", end="")
')" || IS_CURSOR="0"
fi

if [[ "$IS_CURSOR" == "1" ]]; then
  exit 0
fi

if [[ -n "$HOOK_JSON" ]]; then
  printf '%s' "$HOOK_JSON" | NOTIFY_MAILBOX_CONTEXT_MODE=final-response NOTIFY_MAILBOX_SILENT=1 \
    bash "$AGM_SCRIPTS/notify-post.sh" "Claude Code" "Task stopped (failure)" "StopFailure" >/dev/null 2>&1 || true
else
  NOTIFY_MAILBOX_CONTEXT_MODE=final-response NOTIFY_MAILBOX_SILENT=1 \
    bash "$AGM_SCRIPTS/notify-post.sh" "Claude Code" "Task stopped (failure)" "StopFailure" >/dev/null 2>&1 || true
fi
