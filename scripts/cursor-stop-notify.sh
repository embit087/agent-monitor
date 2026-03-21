#!/usr/bin/env bash
# Cursor Agent stop hook — installable version that resolves paths via agm-env.sh.
# Posts to Notify Panel with transcript context, then outputs {} for Cursor.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agm-env.sh"

NOTIFY_MAILBOX_CONTEXT_MODE=final-response \
  bash "$AGM_SCRIPTS/notify-post.sh" "Cursor" "Agent finished" "Stop" >/dev/null 2>&1 || true

printf '%s\n' '{}'
