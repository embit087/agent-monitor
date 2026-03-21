#!/usr/bin/env bash
# Agent Monitor — clean uninstaller.
# Removes: .app bundle, hook scripts, Claude/Cursor hook entries, Fish integration, LaunchAgent.
#
# Usage: bash uninstall.sh [--prefix=PATH]

set -euo pipefail

PREFIX="${AGM_PREFIX:-$HOME/.agm}"
for arg in "$@"; do
  case "$arg" in
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
  esac
done

echo "==> Uninstalling Agent Monitor from $PREFIX"

# ── 1. Stop and remove LaunchAgent ─────────────────────────

LABEL="com.embitious.agent-monitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [[ -f "$PLIST" ]]; then
  echo "   Stopping LaunchAgent..."
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "   Removed $PLIST"
fi

# ── 2. Remove Claude Code hooks ────────────────────────────

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  echo "   Cleaning Claude Code hooks..."
  python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(0)

with open(path, encoding="utf-8") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

MARKERS = [".agm/libexec/", "agent-monitor/scripts/"]
hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(0)

changed = False
for event in ("SessionStart", "Stop"):
    groups = hooks.get(event, [])
    if not isinstance(groups, list):
        continue
    filtered = []
    for group in groups:
        if not isinstance(group, dict):
            filtered.append(group)
            continue
        inner = group.get("hooks", [])
        if not isinstance(inner, list):
            filtered.append(group)
            continue
        kept = [h for h in inner
                if not any(m in (h.get("command", "") if isinstance(h, dict) else "")
                           for m in MARKERS)]
        if kept:
            filtered.append(dict(group, hooks=kept))
        else:
            changed = True
    if filtered != groups:
        changed = True
    if filtered:
        hooks[event] = filtered
    elif event in hooks:
        del hooks[event]
        changed = True

if changed:
    data["hooks"] = hooks
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"   Cleaned {path}")
PY
fi

# ── 3. Remove Cursor hooks ─────────────────────────────────

CURSOR_HOOKS="$HOME/.cursor/hooks.json"
if [[ -f "$CURSOR_HOOKS" ]]; then
  echo "   Cleaning Cursor hooks..."
  python3 - "$CURSOR_HOOKS" <<'PY'
import json, os, sys

path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(0)

with open(path, encoding="utf-8") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

MARKERS = [".agm/libexec/", "agent-monitor/scripts/"]
hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(0)

changed = False
for event in ("sessionStart", "stop"):
    entries = hooks.get(event, [])
    if not isinstance(entries, list):
        continue
    kept = [e for e in entries
            if not (isinstance(e, dict) and
                    any(m in e.get("command", "") for m in MARKERS))]
    if kept != entries:
        changed = True
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]
        changed = True

if changed:
    data["hooks"] = hooks
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"   Cleaned {path}")
PY
fi

# ── 4. Remove Fish integration ──────────────────────────────

FISH_CONF="$HOME/.config/fish/conf.d/99-winid-session.fish"
if [[ -f "$FISH_CONF" ]]; then
  # Only remove if it was installed by us (contains AGM_PREFIX reference)
  if grep -q ".agm/bin/winid\|__AGM_PREFIX__" "$FISH_CONF" 2>/dev/null; then
    rm -f "$FISH_CONF"
    echo "   Removed $FISH_CONF"
  else
    echo "   Kept $FISH_CONF (not installed by Agent Monitor)"
  fi
fi

# ── 5. Remove install prefix ───────────────────────────────

if [[ -d "$PREFIX" ]]; then
  rm -rf "$PREFIX"
  echo "   Removed $PREFIX"
fi

echo
echo "==> Agent Monitor uninstalled."
