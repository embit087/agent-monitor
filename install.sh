#!/usr/bin/env bash
# Agent Monitor — one-click installer.
#
# Usage:
#   bash install.sh                       # fresh install or upgrade
#   bash install.sh --upgrade             # force reinstall even if same version
#   bash install.sh --prefix=~/.agm      # custom install prefix
#   bash install.sh --no-claude           # skip Claude Code hook registration
#   bash install.sh --no-cursor           # skip Cursor hook registration
#   bash install.sh --no-fish             # skip Fish shell integration
#   bash install.sh --no-launchd          # skip launchd LaunchAgent
#   bash install.sh --no-build            # skip build (use existing build/)

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$INSTALLER_DIR/VERSION" 2>/dev/null || echo 0.0.0)"
PREFIX="${AGM_PREFIX:-$HOME/.agm}"

UPGRADE=0
SKIP_CLAUDE=0
SKIP_CURSOR=0
SKIP_FISH=0
SKIP_LAUNCHD=0
SKIP_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=1 ;;
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
    --no-claude) SKIP_CLAUDE=1 ;;
    --no-cursor) SKIP_CURSOR=1 ;;
    --no-fish) SKIP_FISH=1 ;;
    --no-launchd) SKIP_LAUNCHD=1 ;;
    --no-build) SKIP_BUILD=1 ;;
    -h|--help)
      echo "Usage: bash install.sh [--upgrade] [--prefix=PATH] [--no-claude] [--no-cursor] [--no-fish] [--no-launchd] [--no-build]"
      exit 0
      ;;
  esac
done

# ── Prerequisites ───────────────────────────────────────────

check_prerequisites() {
  local missing=0
  for cmd in swift python3 curl; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: $cmd not found on PATH." >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || exit 1
}

# ── Existing install detection ──────────────────────────────

detect_existing() {
  if [[ -f "$PREFIX/share/agm/VERSION" ]]; then
    local existing
    existing="$(cat "$PREFIX/share/agm/VERSION")"
    if [[ "$VERSION" == "$existing" && "$UPGRADE" -eq 0 ]]; then
      echo "Agent Monitor v$VERSION is already installed at $PREFIX."
      echo "Use --upgrade to force reinstall."
      exit 0
    fi
    echo "==> Upgrading v$existing → v$VERSION"
  else
    echo "==> Installing Agent Monitor v$VERSION to $PREFIX"
  fi
}

# ── Build ───────────────────────────────────────────────────

do_build() {
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    if [[ ! -d "$INSTALLER_DIR/build/Agent Monitor.app" ]]; then
      echo "Error: --no-build specified but build/Agent Monitor.app not found." >&2
      echo "Run 'make bundle' first, or omit --no-build." >&2
      exit 1
    fi
    echo "==> Using existing build"
    return
  fi
  echo "==> Building (release)..."
  (cd "$INSTALLER_DIR" && make bundle)
}

# ── Install .app bundle ────────────────────────────────────

install_app_bundle() {
  echo "==> Installing Agent Monitor.app"
  mkdir -p "$PREFIX"
  rm -rf "$PREFIX/Agent Monitor.app"
  cp -R "$INSTALLER_DIR/build/Agent Monitor.app" "$PREFIX/Agent Monitor.app"
  echo "   $PREFIX/Agent Monitor.app"
}

# ── Install CLI symlink ─────────────────────────────────────

install_cli_symlink() {
  mkdir -p "$PREFIX/bin"
  ln -sf "$PREFIX/Agent Monitor.app/Contents/MacOS/agm" "$PREFIX/bin/agm"
  echo "   $PREFIX/bin/agm → Agent Monitor.app"
}

# ── Install winid ───────────────────────────────────────────

install_winid() {
  local winid_src=""

  # Search for winid in common locations
  for candidate in \
    "${NOTIFY_MAILBOX_WINID:-}" \
    "${WINID_SCRIPT:-}" \
    "$INSTALLER_DIR/../winid" \
    "$HOME/embitious/tools/winid" \
    "$HOME/tools/winid" \
    "$(command -v winid 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      winid_src="$candidate"
      break
    fi
  done

  if [[ -n "$winid_src" ]]; then
    cp "$winid_src" "$PREFIX/bin/winid"
    chmod +x "$PREFIX/bin/winid"
    echo "   $PREFIX/bin/winid (from $winid_src)"
  else
    echo "   Warning: winid not found. Copy it manually to $PREFIX/bin/winid" >&2
  fi
}

# ── Install hook scripts ───────────────────────────────────

install_scripts() {
  echo "==> Installing hook scripts"
  mkdir -p "$PREFIX/libexec/scripts"

  for script in agm-env.sh notify-post.sh winid-session-register.sh \
                claude-stop-notify.sh claude-sessionstart-notify.sh \
                cursor-stop-notify.sh notify-hook-context.py; do
    if [[ -f "$INSTALLER_DIR/scripts/$script" ]]; then
      cp "$INSTALLER_DIR/scripts/$script" "$PREFIX/libexec/scripts/$script"
      chmod +x "$PREFIX/libexec/scripts/$script"
    fi
  done
  echo "   $PREFIX/libexec/scripts/"
}

# ── Write VERSION marker ───────────────────────────────────

write_version() {
  mkdir -p "$PREFIX/share/agm"
  echo "$VERSION" > "$PREFIX/share/agm/VERSION"
}

# ── Claude Code hook registration ──────────────────────────

install_claude_hooks() {
  [[ "$SKIP_CLAUDE" -eq 1 ]] && { echo "==> Skipped Claude Code hooks (--no-claude)"; return; }
  echo "==> Registering Claude Code hooks"

  local settings="$HOME/.claude/settings.json"
  local sessionstart_cmd="bash $PREFIX/libexec/scripts/claude-sessionstart-notify.sh"
  local stop_cmd="bash $PREFIX/libexec/scripts/claude-stop-notify.sh"

  python3 - "$settings" "$sessionstart_cmd" "$stop_cmd" <<'PYTHON'
import json
import os
import sys

settings_path, sessionstart_cmd, stop_cmd = sys.argv[1:4]

# Read existing settings
if os.path.isfile(settings_path):
    with open(settings_path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            print(f"  Error: invalid JSON in {settings_path}", file=sys.stderr)
            sys.exit(1)
else:
    os.makedirs(os.path.dirname(settings_path) or ".", exist_ok=True)
    data = {}

hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}

MARKERS = [
    "agent-monitor/scripts/",
    ".agm/libexec/",
    "claude-stop-mailbox.sh",
    "claude-sessionstart-mailbox.sh",
    "claude-stop-notify.sh",
    "claude-sessionstart-notify.sh",
]

def remove_agm_entries(event_hooks):
    """Remove hook groups whose commands match AGM markers."""
    if not isinstance(event_hooks, list):
        return []
    result = []
    for group in event_hooks:
        if not isinstance(group, dict):
            result.append(group)
            continue
        inner = group.get("hooks", [])
        if not isinstance(inner, list):
            result.append(group)
            continue
        filtered = [h for h in inner
                    if not any(m in (h.get("command", "") if isinstance(h, dict) else "")
                               for m in MARKERS)]
        if filtered:
            group = dict(group, hooks=filtered)
            result.append(group)
    return result

for event in ("SessionStart", "Stop"):
    hooks[event] = remove_agm_entries(hooks.get(event, []))

# Prepend new hooks
hooks.setdefault("SessionStart", []).insert(0, {
    "hooks": [{"type": "command", "command": sessionstart_cmd}]
})
hooks.setdefault("Stop", []).insert(0, {
    "hooks": [{"type": "command", "command": stop_cmd}]
})

data["hooks"] = hooks

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"   Updated {settings_path}")
print(f"   SessionStart → {sessionstart_cmd}")
print(f"   Stop → {stop_cmd}")
PYTHON
}

# ── Cursor hook registration ──────────────────────────────

install_cursor_hooks() {
  [[ "$SKIP_CURSOR" -eq 1 ]] && { echo "==> Skipped Cursor hooks (--no-cursor)"; return; }
  echo "==> Registering Cursor hooks"

  local target="$HOME/.cursor/hooks.json"
  local register_sh="$PREFIX/libexec/scripts/winid-session-register.sh"
  local stop_sh="$PREFIX/libexec/scripts/cursor-stop-notify.sh"

  python3 - "$target" "$register_sh" "$stop_sh" <<'PY'
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
            print(f"  Error: invalid JSON in {target}: {e}", file=sys.stderr)
            sys.exit(1)
else:
    data = {}

if not isinstance(data, dict):
    data = {}

data["version"] = data.get("version", 1)
hooks = data.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    hooks = {}

MARKERS = [
    "winid-session-register.sh",
    "cursor-stop-notify.sh",
    "mailbox-winid-register.sh",
    "cursor-stop-mailbox.sh",
    ".agm/libexec/",
    "agent-monitor/scripts/",
]

def without_agm(entries):
    if not entries:
        return []
    out = []
    for item in entries:
        if not isinstance(item, dict):
            out.append(item)
            continue
        cmd = item.get("command", "")
        if isinstance(cmd, str) and any(m in cmd for m in MARKERS):
            continue
        out.append(item)
    return out

def normalize_list(key):
    raw = hooks.get(key)
    if raw is None:
        return []
    if not isinstance(raw, list):
        return []
    return raw

session_start = without_agm(normalize_list("sessionStart"))
stop_hooks = without_agm(normalize_list("stop"))

new_start = {"command": f"bash {register_abs}"}
new_stop = {"command": f"bash {stop_abs}", "loop_limit": None}

hooks["sessionStart"] = [new_start] + session_start
hooks["stop"] = [new_stop] + stop_hooks
data["hooks"] = hooks

with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"   Updated {target}")
print(f"   sessionStart → {register_abs}")
print(f"   stop → {stop_abs}")
PY
}

# ── Fish shell integration ─────────────────────────────────

install_fish() {
  [[ "$SKIP_FISH" -eq 1 ]] && { echo "==> Skipped Fish integration (--no-fish)"; return; }

  if ! command -v fish &>/dev/null; then
    echo "==> Skipped Fish integration (fish not found)"
    return
  fi

  echo "==> Installing Fish shell integration"
  local fish_conf_d="$HOME/.config/fish/conf.d"
  mkdir -p "$fish_conf_d"
  sed "s|__AGM_PREFIX__|$PREFIX|g" "$INSTALLER_DIR/packaging/99-winid-session.fish" \
    > "$fish_conf_d/99-winid-session.fish"
  echo "   $fish_conf_d/99-winid-session.fish"
}

# ── launchd LaunchAgent ────────────────────────────────────

install_launchd() {
  [[ "$SKIP_LAUNCHD" -eq 1 ]] && { echo "==> Skipped LaunchAgent (--no-launchd)"; return; }

  echo "==> Installing LaunchAgent"
  local plist_dir="$HOME/Library/LaunchAgents"
  local plist="$plist_dir/com.embitious.agent-monitor.plist"
  local label="com.embitious.agent-monitor"

  mkdir -p "$plist_dir"
  mkdir -p "$HOME/Library/Logs/AgentMonitor"

  # Stop existing if running
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true

  # Write plist with HOME expanded
  sed "s|__HOME__|$HOME|g" "$INSTALLER_DIR/packaging/com.embitious.agent-monitor.plist" \
    > "$plist"

  # Load and start
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "   $plist"
  echo "   Manage: launchctl start/stop $label"
}

# ── Summary ─────────────────────────────────────────────────

print_summary() {
  local launchd_status="installed"
  [[ "$SKIP_LAUNCHD" -eq 1 ]] && launchd_status="skipped"
  local fish_status="installed"
  [[ "$SKIP_FISH" -eq 1 ]] && fish_status="skipped"
  command -v fish &>/dev/null || fish_status="skipped (fish not found)"

  cat <<EOF

================================================================
  Agent Monitor v${VERSION} installed successfully
================================================================

  Install prefix:  ${PREFIX}
  App bundle:      ${PREFIX}/Agent Monitor.app
  CLI binary:      ${PREFIX}/bin/agm
  Hook scripts:    ${PREFIX}/libexec/scripts/
  Fish shell:      ${fish_status}
  LaunchAgent:     ${launchd_status}

  Start now:       open "${PREFIX}/Agent Monitor.app"
  Stop service:    launchctl bootout gui/\$(id -u)/com.embitious.agent-monitor
  Restart:         launchctl kickstart -k gui/\$(id -u)/com.embitious.agent-monitor
  Uninstall:       bash ${INSTALLER_DIR}/uninstall.sh

  Add to PATH (optional):
    export PATH="${PREFIX}/bin:\$PATH"

================================================================
EOF
}

# ── Main ────────────────────────────────────────────────────

check_prerequisites
detect_existing
do_build
install_app_bundle
install_cli_symlink
install_winid
install_scripts
write_version
install_claude_hooks
install_cursor_hooks
install_fish
install_launchd
print_summary
