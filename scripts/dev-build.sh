#!/bin/bash
# Build, sign, and (re)launch the debug app. Signs with the stable "ShortcutWheel
# Dev" identity if present (so TCC grants persist across rebuilds), otherwise falls
# back to ad-hoc. Run ./scripts/dev-signing-setup.sh once to create that identity.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="ShortcutWheel Dev"
# Not `-v`: a self-signed dev cert is untrusted, so it's absent from the valid-only
# list, but codesign can still sign with it.
if security find-identity -p codesigning | grep -q "$NAME"; then
    SIGN="$NAME"
else
    SIGN="-"
    echo "warning: '$NAME' not found — using ad-hoc signing (grants will reset each build)."
    echo "         Run ./scripts/dev-signing-setup.sh once to fix this."
fi

xcodegen generate >/dev/null
xcodebuild -scheme ShortcutWheel -configuration Debug build 2>&1 | tail -2

APP="$(find ~/Library/Developer/Xcode/DerivedData/ShortcutWheel-*/Build/Products/Debug \
    -maxdepth 1 -name 'ShortcutWheel.app' 2>/dev/null | head -1)"

codesign --force --deep --sign "$SIGN" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

pkill -x ShortcutWheel 2>/dev/null || true
sleep 1
open "$APP"
echo "Launched: $APP  (signed: $SIGN)"
