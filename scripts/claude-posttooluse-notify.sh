#!/usr/bin/env bash
# Claude Code PostToolUse hook for Agent Monitor.
# Posts a compact notification for each tool execution (silent — no macOS banner).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agm-env.sh"

HOOK_JSON=""
if [ ! -t 0 ]; then
  HOOK_JSON="$(cat || true)"
fi

if [[ -z "$HOOK_JSON" ]]; then
  exit 0
fi

IS_CURSOR="$(printf '%s' "$HOOK_JSON" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
    print("1" if payload.get("cursor_version") else "0", end="")
except Exception:
    print("0", end="")
')" || IS_CURSOR="0"

if [[ "$IS_CURSOR" == "1" ]]; then
  exit 0
fi

printf '%s' "$HOOK_JSON" | python3 -c '
import json, sys

try:
    hook = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = hook.get("tool_name", "unknown")
inp = hook.get("tool_input") or {}

# Build concise summary from tool input
detail = ""
if tool in ("Read", "read"):
    detail = inp.get("file_path", inp.get("path", ""))
elif tool in ("Write", "write", "Edit", "edit"):
    detail = inp.get("file_path", inp.get("path", ""))
elif tool in ("Bash", "bash"):
    detail = (inp.get("command") or "")[:120]
elif tool in ("Grep", "grep"):
    detail = inp.get("pattern", "")
elif tool in ("Glob", "glob"):
    detail = inp.get("pattern", "")
elif tool in ("Agent", "agent"):
    detail = inp.get("description", inp.get("prompt", ""))[:100]
else:
    for v in inp.values():
        if isinstance(v, str) and v.strip():
            detail = v.strip()[:100]
            break

body = f"{tool}: {detail}" if detail else tool

sid = ""
for key in ("session_id", "conversation_id", "sessionId"):
    s = hook.get(key)
    if s and str(s).strip():
        sid = str(s).strip()
        break

payload = {
    "title": "Claude Code",
    "body": body[:250],
    "source": "PostToolUse",
    "silent": True,
}
if sid:
    payload["action"] = sid

print(json.dumps(payload))
' | curl -sS -X POST \
    "${NOTIFY_MAILBOX_URL:-http://127.0.0.1:${NOTIFY_MAILBOX_PORT:-3850}}/api/notify" \
    -H "Content-Type: application/json" \
    ${NOTIFY_MAILBOX_SECRET:+-H "Authorization: Bearer $NOTIFY_MAILBOX_SECRET"} \
    -d @- >/dev/null 2>&1 || true
