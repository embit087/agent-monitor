#!/usr/bin/env bash
# Merge Notify Panel Cursor hooks into ~/.cursor/hooks.json so they run for Cursor CLI
# from any working directory (user-level hooks). Project-only .cursor/hooks.json is skipped
# when the workspace root is not this repo.
#
# Usage: bash scripts/install-cursor-notify-hooks.sh
# Re-run after moving the repo (updates absolute paths).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTER_SH="$REPO_ROOT/scripts/winid-session-register.sh"
STOP_WRAP="$REPO_ROOT/scripts/cursor-stop-notify.sh"
TARGET="${HOME}/.cursor/hooks.json"

for f in "$REGISTER_SH" "$STOP_WRAP"; do
  if [[ ! -f "$f" ]]; then
    echo "install-cursor-notify-hooks: missing $f" >&2
    exit 1
  fi
done

chmod +x "$REGISTER_SH" "$REPO_ROOT/scripts/notify-post.sh" "$STOP_WRAP" 2>/dev/null || true

python3 - "$TARGET" "$REGISTER_SH" "$STOP_WRAP" <<'PY'
import json
import os
import sys

target, register_abs, stop_abs = sys.argv[1:4]

os.makedirs(os.path.dirname(target) or ".", exist_ok=True)

if os.path.isfile(target):
    with open(target, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"install-cursor-notify-hooks: invalid JSON in {target}: {e}", file=sys.stderr)
            sys.exit(1)
else:
    data = {}

if not isinstance(data, dict):
    print("install-cursor-notify-hooks: hooks.json must be a JSON object", file=sys.stderr)
    sys.exit(1)

data["version"] = data.get("version", 1)
hooks = data.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    print("install-cursor-notify-hooks: hooks key must be an object", file=sys.stderr)
    sys.exit(1)

def without_notify_hooks(entries, needle: str):
    if not entries:
        return []
    out = []
    for item in entries:
        if not isinstance(item, dict):
            out.append(item)
            continue
        cmd = item.get("command", "")
        if isinstance(cmd, str) and needle in cmd:
            continue
        out.append(item)
    return out

def normalize_list(key: str):
    raw = hooks.get(key)
    if raw is None:
        return []
    if not isinstance(raw, list):
        print(f"install-cursor-notify-hooks: hooks.{key} must be an array — fixing to []", file=sys.stderr)
        return []
    return raw

session_start = without_notify_hooks(normalize_list("sessionStart"), "winid-session-register.sh")
stop_hooks = without_notify_hooks(normalize_list("stop"), "cursor-stop-notify.sh")
# Remove legacy paths from older installs
session_start = without_notify_hooks(session_start, "mailbox-winid-register.sh")
stop_hooks = without_notify_hooks(stop_hooks, "cursor-stop-mailbox.sh")

new_start = {"command": f"bash {register_abs}"}
new_stop = {"command": f"bash {stop_abs}", "loop_limit": None}

hooks["sessionStart"] = [new_start] + session_start
hooks["stop"] = [new_stop] + stop_hooks
data["hooks"] = hooks

with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Wrote {target}")
print("  sessionStart → winid-session-register.sh")
print("  stop → cursor-stop-notify.sh (loop_limit: null)")
print("Restart Cursor / start a new agent session so hook config reloads.")
PY
