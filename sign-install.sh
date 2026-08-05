#!/bin/bash
# Build, Developer-ID sign, and install to /Applications. Local convenience for
# a properly signed copy — CI does its own signing and notarisation.
set -euo pipefail
cd "$(dirname "$0")"
ID="Developer ID Application: TV Labs LTD (DR9WWQT8R8)"

osascript -e 'tell application "Wick" to quit' 2>/dev/null || true
sleep 0.4; pkill -x Wick 2>/dev/null || true; sleep 0.3

./build.sh >/dev/null
rm -rf /Applications/Wick.app
cp -R build/Wick.app /Applications/Wick.app
APP=/Applications/Wick.app

codesign --force --options runtime --timestamp --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

open -a "$APP"
echo "✓ signed + installed /Applications/Wick.app"
