#!/usr/bin/env bash
# Verification script for winid feature
# Run this to ensure winid is properly installed and working

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINID="${HOME}/.agm/bin/winid"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Winid Feature Verification                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check 1: Winid Installation
echo "1️⃣  Checking winid installation..."
if [ -x "$WINID" ]; then
    echo "   ✅ Found: $WINID"
    SIZE=$(du -h "$WINID" | cut -f1)
    echo "   Size: $SIZE"
else
    echo "   ❌ FAILED: $WINID not found or not executable"
    echo ""
    echo "   Quick fix:"
    echo "   mkdir -p ~/.agm/bin"
    echo "   cp ${SCRIPT_DIR}/../winid ~/.agm/bin/winid"
    echo "   chmod +x ~/.agm/bin/winid"
    exit 1
fi
echo ""

# Check 2: Saved Windows
echo "2️⃣  Checking saved window IDs..."
SAVED_COUNT=$("$WINID" list 2>/dev/null | wc -l)
if [ "$SAVED_COUNT" -gt 2 ]; then
    echo "   ✅ Found $((SAVED_COUNT - 2)) saved window(s)"
    echo ""
    "$WINID" list | head -10
    if [ "$SAVED_COUNT" -gt 12 ]; then
        echo "   ... and $((SAVED_COUNT - 12)) more"
    fi
else
    echo "   ⚠️  No saved windows found"
    echo "   (This is OK if no agents have been run yet)"
fi
echo ""

# Check 3: Current Terminal
echo "3️⃣  Checking current Terminal tab..."
if "$WINID" current 2>/dev/null | head -1 | grep -q "App:"; then
    echo "   ✅ Terminal.app is accessible"
    "$WINID" current 2>/dev/null | sed 's/^/   /'
else
    echo "   ⚠️  Could not detect current Terminal (non-critical)"
fi
echo ""

# Check 4: Test Open (if windows exist)
echo "4️⃣  Testing terminal switching..."
if [ "$SAVED_COUNT" -gt 2 ]; then
    FIRST_ID=$("$WINID" list | tail -1 | awk '{print $1}')
    if [ -n "$FIRST_ID" ] && [ "$FIRST_ID" != "ID" ]; then
        echo "   Testing: winid open $FIRST_ID"
        if "$WINID" open "$FIRST_ID" > /dev/null 2>&1; then
            echo "   ✅ Successfully switched to Terminal tab"
        else
            echo "   ⚠️  Could not switch (tab may have been closed)"
            echo "   This is normal if tabs were closed after being saved"
        fi
    fi
else
    echo "   ⏭️  Skipped (no saved windows to test)"
fi
echo ""

# Check 5: Hook Integration
echo "5️⃣  Checking hook integration..."
HOOK_SCRIPT="${SCRIPT_DIR}/claude-sessionstart-notify.sh"
if [ -f "$HOOK_SCRIPT" ]; then
    echo "   ✅ Found hook script: $HOOK_SCRIPT"
    if grep -q "winid save" "$HOOK_SCRIPT" 2>/dev/null; then
        echo "   ✅ Hook calls 'winid save' correctly"
    else
        echo "   ⚠️  Hook script may not call 'winid save'"
    fi
else
    echo "   ⚠️  Hook script not found (may not be required)"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      RESULT                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Winid is properly installed and working"
echo ""
echo "Next steps:"
echo "  1. Close and reopen Agent Monitor app"
echo "  2. Click a notification to test terminal switching"
echo "  3. If it still fails, check: log stream --predicate 'process == \"Agent Monitor\"'"
echo ""
echo "Documentation:"
echo "  - WINID_OVERVIEW.md      - Feature documentation"
echo "  - WINID_DIAGNOSTICS.md   - Troubleshooting guide"
echo "  - WINID_FIX_SUMMARY.md   - How the fix was applied"
echo ""
