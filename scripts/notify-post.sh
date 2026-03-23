#!/usr/bin/env bash
# POST to the local Notify Panel app (127.0.0.1) from Claude Code Stop hook, Cursor `stop`, or manual use.
#
# When stdin is hook JSON (non-TTY), reads session_id (Claude), else conversation_id (Cursor),
# else sessionId, and sends it as "action" so the app can winid open that id.
# Needs sessionStart + winid-session-register.sh to winid save that same id once.
#
# Fallback when stdin is not hook JSON (e.g. manual run from a TTY): WINID_SESSION_UUID / winid session.
#
# Usage: notify-post.sh [title] [body] [source]
# Env: NOTIFY_MAILBOX_PORT, NOTIFY_MAILBOX_SECRET, NOTIFY_MAILBOX_URL, WINID_SCRIPT,
#      MAILBOX_PREFER_WINID=1 — force winid/Fish session id instead of Claude session_id
#      NOTIFY_MAILBOX_CONTEXT_MODE=final-response|latest-user-query — derive body/details from transcript_path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agm-env.sh"

PORT="${NOTIFY_MAILBOX_PORT:-3850}"
HOST_PORT_URL="${NOTIFY_MAILBOX_URL:-http://127.0.0.1:${PORT}}"
URL_BASE="${HOST_PORT_URL%/}"
URL="${URL_BASE}/api/notify"

TITLE="${1:-Notification}"
BODY="${2:-Task completed}"
SOURCE="${3:-}"

winid_exe() {
  if [[ -n "${AGM_WINID:-}" && -x "$AGM_WINID" ]]; then
    echo "$AGM_WINID"
    return 0
  fi
  if command -v winid &>/dev/null; then
    command -v winid
    return 0
  fi
  return 1
}

derive_hook_context_json() {
  local mode="${NOTIFY_MAILBOX_CONTEXT_MODE:-}"
  if [[ -z "$mode" || -z "$HOOK_JSON" ]]; then
    return 0
  fi

  local derived=""
  derived="$(printf '%s' "$HOOK_JSON" | python3 "$SCRIPT_DIR/notify-hook-context.py" "$BODY" "$mode" 2>/dev/null)" || derived=""
  printf '%s' "$derived"
}

HOOK_JSON=""
if [ ! -t 0 ]; then
  HOOK_JSON="$(cat || true)"
fi

HOOK_SID=""
if [[ -n "$HOOK_JSON" && "${MAILBOX_PREFER_WINID:-}" != "1" ]]; then
  HOOK_SID="$(printf '%s' "$HOOK_JSON" | python3 -c '
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
' 2>/dev/null)" || HOOK_SID=""
fi

from_winid() {
  if [[ -n "${WINID_SESSION_UUID:-}" ]]; then
    echo "$WINID_SESSION_UUID"
    return 0
  fi
  local exe
  if exe="$(winid_exe)"; then
    local out
    out="$("$exe" session 2>/dev/null)" || out=""
    echo "${out//$'\r'/}"
    return 0
  fi
  echo ""
  return 1
}

SID=""
if [[ -n "$HOOK_SID" ]]; then
  SID="$HOOK_SID"
else
  SID="$(from_winid)" || SID=""
fi
SID="${SID//$'\n'/}"
SID="${SID//$'\r'/}"

HOOK_CONTEXT_JSON="$(derive_hook_context_json)"

JSON="$(
  TITLE="$TITLE" BODY="$BODY" SOURCE="$SOURCE" ACTION="$SID" HOOK_CONTEXT_JSON="$HOOK_CONTEXT_JSON" python3 -c '
import json, os
body = os.environ.get("BODY") or "(no message)"
ctx = None
ctx_raw = os.environ.get("HOOK_CONTEXT_JSON") or ""
if ctx_raw:
    try:
        parsed = json.loads(ctx_raw)
        if isinstance(parsed, dict):
            ctx = parsed
            candidate = parsed.get("body")
            if isinstance(candidate, str) and candidate.strip():
                body = candidate
        elif isinstance(parsed, str) and parsed.strip():
            body = parsed
    except Exception:
        if ctx_raw.strip():
            body = ctx_raw
p = {
    "title": os.environ.get("TITLE") or "Notification",
    "body": body,
}
src = (os.environ.get("SOURCE") or "").strip()
if src:
    p["source"] = src
a = (os.environ.get("ACTION") or "").strip()
if a:
    p["action"] = a
silent = (os.environ.get("NOTIFY_MAILBOX_SILENT") or "").strip().lower() in ("1", "true", "yes")
if silent:
    p["silent"] = True
if isinstance(ctx, dict):
    summary = (ctx.get("summary") or "").strip()
    if summary:
        p["summary"] = summary
    request = (ctx.get("request") or "").strip()
    if request:
        p["request"] = request
    raw_json = (ctx.get("raw_response_json") or "").strip()
    if raw_json:
        p["raw_response_json"] = raw_json
print(json.dumps(p))
'
)"

CURL_ARGS=( -sS -X POST "$URL" -H "Content-Type: application/json" -d "$JSON" )
if [[ -n "${NOTIFY_MAILBOX_SECRET:-}" ]]; then
  CURL_ARGS+=( -H "Authorization: Bearer ${NOTIFY_MAILBOX_SECRET}" )
fi

exec curl "${CURL_ARGS[@]}"
