# Winid Feature Diagnostics & Fix

## Problem Summary
The `winid open <id>` command stopped working in the Agent Monitor app. When clicking notifications, the terminal window fails to switch.

## Root Cause
**WinidLocator.swift** uses `#filePath` to calculate the path to the `winid` script:

```swift
let here = URL(fileURLWithPath: #filePath, isDirectory: false)
let pkgRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
return pkgRoot.deletingLastPathComponent().appendingPathComponent("winid")
```

### Why This Fails
- In **development** (running from source), `#filePath` = `Sources/agm/WinidLocator.swift` ✓ Works correctly
- In **production** (compiled app), `#filePath` = path inside the `.app` bundle, e.g., `/Applications/Agent Monitor.app/Contents/MacOS/...` ✗ Path calculation fails

The production path doesn't lead back to `~/embitious/tools/winid`, so the repo-adjacent fallback can't find the script.

## Current Fallback Behavior
WinidLocator tries these locations in order:
1. `NOTIFY_MAILBOX_WINID` env var
2. `WINID_SCRIPT` env var
3. `AGM_PREFIX/bin/winid` (default: `~/.agm/bin/winid`)
4. `~/.local/bin/winid`
5. `/usr/local/bin/winid`
6. **Repo-adjacent fallback** (broken when compiled) ← THIS IS THE ISSUE

## Test Results
✓ Script exists and is executable: `/Users/objsinc-macair-00/embitious/tools/winid`
✓ Script works when called directly: `winid open <id>` succeeds
✗ App can't locate it when running as compiled macOS app
✓ 17+ saved window IDs exist in `~/.winids/`

## Solutions (in order of reliability)

### 1. **Install winid to standard location** (Most Reliable)
```bash
mkdir -p ~/.agm/bin
cp /Users/objsinc-macair-00/embitious/tools/winid ~/.agm/bin/winid
chmod +x ~/.agm/bin/winid
```
✓ No code changes needed
✓ Works in dev and production
✓ Survives app reinstalls

### 2. **Set environment variable** (Quick Workaround)
Export before running the app:
```bash
export WINID_SCRIPT=/Users/objsinc-macair-00/embitious/tools/winid
open /Applications/Agent\ Monitor.app
```
✓ Works immediately
✗ Must be set every time
✗ Won't persist for drag-launch

### 3. **Fix WinidLocator.resolve()** (Code Fix)
Add detection for when running as a compiled app:
```swift
// In PanelModel.init(), provide app bundle directory as hint
let bundleDir = Bundle.main.bundlePath // e.g., /Applications/Agent Monitor.app
// Then add bundle-relative search path to WinidLocator
```
✓ Works without manual setup
✗ Requires recompile
✗ Still relies on knowing app location

### 4. **Auto-copy during build** (Best Long-term)
Add a build phase or install script to copy winid:
```bash
cp "$SOURCE_DIR/../tools/winid" "$BUILT_PRODUCTS_DIR/$EXECUTABLE_FOLDER_PATH/"
```
✓ Bakes script into app bundle
✓ Always available
✗ Bloats app size slightly
✗ Creates copy outside source control

## Recommendation
**Start with Solution 1** (install to `~/.agm/bin/`). It's:
- Zero-friction (one-time setup)
- Doesn't require code changes
- Matches the app's own documentation (WinidLocator checks here by default)
- Works for both dev and production

Then consider Solution 3 if you want future app launches to work automatically.

## Verification Checklist
After applying a fix, verify:
- [ ] `winid list` shows saved window IDs
- [ ] `winid open <any-id>` focuses that Terminal tab
- [ ] Clicking a notification in Agent Monitor switches terminal
- [ ] No errors in Console.app for the Agent Monitor process
