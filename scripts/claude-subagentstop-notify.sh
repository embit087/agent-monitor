#!/usr/bin/env bash
# Claude Code SubagentStop hook for Agent Monitor.
# Posts a notification when a subagent finishes (silent — no macOS banner).

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

agent_type = hook.get("agent_type", "subagent")
last_msg = (hook.get("last_assistant_message") or "").strip()

# Concise body for compact display
if last_msg:
    preview = last_msg.replace("\n", " ")[:150]
    body = f"{agent_type}: {preview}"
else:
    body = f"{agent_type} finished"

sid = ""
for key in ("session_id", "conversation_id", "sessionId"):
    s = hook.get(key)
    if s and str(s).strip():
        sid = str(s).strip()
        break

payload = {
    "title": "Claude Code",
    "body": body[:250],
    "source": "SubagentStop",
    "silent": True,
}
if sid:
    payload["action"] = sid
if last_msg:
    payload["summary"] = last_msg[:8000]

print(json.dumps(payload))
' | curl -sS -X POST \
    "${NOTIFY_MAILBOX_URL:-http://127.0.0.1:${NOTIFY_MAILBOX_PORT:-3850}}/api/notify" \
    -H "Content-Type: application/json" \
    ${NOTIFY_MAILBOX_SECRET:+-H "Authorization: Bearer $NOTIFY_MAILBOX_SECRET"} \
    -d @- >/dev/null 2>&1 || true
