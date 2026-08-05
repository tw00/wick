#!/bin/bash
# Build and install to /Applications, so the wick:// scheme resolves and
# "Launch at login" can register. Local dev convenience.
set -euo pipefail
cd "$(dirname "$0")"

pkill -x Wick 2>/dev/null || true
sleep 0.3

./build.sh >/dev/null
rm -rf /Applications/Wick.app
cp -R build/Wick.app /Applications/Wick.app

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f /Applications/Wick.app 2>/dev/null || true

open -a /Applications/Wick.app
echo "✓ installed /Applications/Wick.app"
