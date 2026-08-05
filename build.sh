#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Wick.app"
NAME="Wick"

echo "› compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos14.0 \
    Sources/*.swift \
    -framework SwiftUI -framework AppKit -framework QuartzCore -framework ServiceManagement \
    -o "$APP/Contents/MacOS/$NAME"

echo "› bundling…"
cp Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "› signing (ad-hoc)…"
codesign --force --sign - "$APP" >/dev/null

echo "✓ built $APP"
