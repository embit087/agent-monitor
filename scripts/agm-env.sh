#!/usr/bin/env bash
# Shared environment for Agent Monitor hook scripts.
# Source this from any hook script to resolve AGM_PREFIX, AGM_WINID, AGM_SCRIPTS.
#
# Resolution order for AGM_PREFIX:
#   1. AGM_PREFIX env var (explicit override)
#   2. Derive from script location if in installed layout (*/libexec/scripts/)
#   3. ~/.agm if it exists
#   4. Repo root (development mode — scripts/ is a direct child)

if [[ -z "${AGM_PREFIX:-}" ]]; then
  _agm_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "$_agm_self_dir" == */libexec/scripts ]]; then
    # Installed layout: ~/.agm/libexec/scripts/ → ~/.agm
    AGM_PREFIX="$(cd "$_agm_self_dir/../.." && pwd)"
  elif [[ -d "$HOME/.agm/bin" ]]; then
    AGM_PREFIX="$HOME/.agm"
  else
    # Development mode: scripts/ → repo root
    AGM_PREFIX="$(cd "$_agm_self_dir/.." && pwd)"
  fi
  unset _agm_self_dir
fi
export AGM_PREFIX

# Default port for the Tauri-based Agent Monitor
export NOTIFY_MAILBOX_PORT="${NOTIFY_MAILBOX_PORT:-3850}"

# Resolve winid path
if [[ -n "${NOTIFY_MAILBOX_WINID:-}" && -x "${NOTIFY_MAILBOX_WINID}" ]]; then
  AGM_WINID="$NOTIFY_MAILBOX_WINID"
elif [[ -n "${WINID_SCRIPT:-}" && -x "${WINID_SCRIPT}" ]]; then
  AGM_WINID="$WINID_SCRIPT"
elif [[ -x "$AGM_PREFIX/bin/winid" ]]; then
  AGM_WINID="$AGM_PREFIX/bin/winid"
elif command -v winid &>/dev/null; then
  AGM_WINID="$(command -v winid)"
elif [[ -x "$HOME/.local/bin/winid" ]]; then
  AGM_WINID="$HOME/.local/bin/winid"
elif [[ -x "/usr/local/bin/winid" ]]; then
  AGM_WINID="/usr/local/bin/winid"
else
  # Development fallback: sibling to repo root
  _agm_dev_winid="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/winid"
  if [[ -x "$_agm_dev_winid" ]]; then
    AGM_WINID="$_agm_dev_winid"
  else
    AGM_WINID=""
  fi
  unset _agm_dev_winid
fi
export AGM_WINID

# Resolve scripts directory
if [[ -d "$AGM_PREFIX/libexec/scripts" ]]; then
  AGM_SCRIPTS="$AGM_PREFIX/libexec/scripts"
elif [[ -d "$AGM_PREFIX/scripts" ]]; then
  # Development mode
  AGM_SCRIPTS="$AGM_PREFIX/scripts"
else
  AGM_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
export AGM_SCRIPTS
