# Global `winid` command + per-session WINID_SESSION_UUID registration.
# Installed by Agent Monitor (install.sh). Re-run install.sh after moving the install prefix.
# Override winid location: set -Ux WINID_SCRIPT /path/to/winid

function __winid_executable
    if set -q WINID_SCRIPT
        test -x "$WINID_SCRIPT"; and echo $WINID_SCRIPT; and return
    end
    set -l installed "__AGM_PREFIX__/bin/winid"
    test -x "$installed"; and echo $installed; and return
    set -l local "$HOME/.local/bin/winid"
    test -x "$local"; and echo $local; and return
    set -l global /usr/local/bin/winid
    test -x "$global"; and echo $global; and return
end

function winid
    set -l exe (__winid_executable)
    if test -z "$exe"
        echo "winid: script not found. Set: set -Ux WINID_SCRIPT /path/to/winid" >&2
        return 127
    end
    command $exe $argv
end

status is-interactive; or return
set -q WINID_SESSION_UUID; and return

set -gx WINID_SESSION_UUID (uuidgen 2>/dev/null | string lower)
test -n "$WINID_SESSION_UUID"; or set -gx WINID_SESSION_UUID (python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null)
test -n "$WINID_SESSION_UUID"; or set -gx WINID_SESSION_UUID local-(date +%s)-$fish_pid-(random 100000 999999)

echo "WINID_SESSION_UUID=$WINID_SESSION_UUID"

if set -q SSH_CLIENT; or set -q SSH_CONNECTION
    return
end

set -l cli (__winid_executable)
if test -n "$cli"
    command $cli save $WINID_SESSION_UUID &>/dev/null
end
