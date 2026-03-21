Re-register this terminal's winid session so the monitor can focus it.

Use this when the user reports that clicking a session in the monitor doesn't switch to the correct terminal, or that the session ID was lost.

## Steps

1. Resolve the session ID. Try `CLAUDE_CODE_SESSION_ID` first, then fall back to `WINID_SESSION_UUID`, then `winid session`:
   ```
   SID="${CLAUDE_CODE_SESSION_ID:-${WINID_SESSION_UUID:-}}"
   if [ -z "$SID" ]; then
     source scripts/agm-env.sh 2>/dev/null
     SID=$("$AGM_WINID" session 2>/dev/null || true)
   fi
   echo "$SID"
   ```
   If all are empty, tell the user no session ID could be resolved and stop.

2. Bring Terminal to the foreground, save the winid, then re-activate the previous app so the user's workflow is not disrupted:
   ```
   source scripts/agm-env.sh 2>/dev/null
   osascript -e '
     tell application "System Events"
       set frontApp to name of first application process whose frontmost is true
     end tell
     tell application "Terminal" to activate
     delay 0.3
     do shell script "'"$AGM_WINID"' save '"$SID"'"
     tell application frontApp to activate
   '
   ```
   If `AGM_WINID` is empty or the command fails, tell the user that `winid` could not be found.

3. Append the TTY if missing from the saved file:
   ```
   file="$HOME/.winids/$SID"
   if [ -f "$file" ] && ! grep -q '^tty=' "$file" 2>/dev/null; then
     tty_val=$(osascript -e 'tell application "Terminal" to try
       return (tty of selected tab of front window) as string
     end try' 2>/dev/null | tr -d '\r\n')
     if [ -n "$tty_val" ]; then
       echo "tty=$tty_val" >> "$file"
     fi
   fi
   ```

4. Confirm to the user that the session was re-registered, showing the session ID and the path to the saved file (`~/.winids/<id>`).
