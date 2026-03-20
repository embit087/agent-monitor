#!/usr/bin/env bash
# Cursor Agent `stop` hook: POST to local notify panel, then print StopHookOutput JSON.
# Stdin is Cursor hook JSON (includes conversation_id); stdout must be hook JSON only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NOTIFY_MAILBOX_CONTEXT_MODE=final-response \
  bash "$REPO_ROOT/scripts/notify-post.sh" "Cursor" "Agent finished" >/dev/null 2>&1 || true
printf '%s\n' '{}'
