#!/bin/bash
# Turn Resources/icon_1024.png into Resources/AppIcon.icns.
# Drop a new 1024×1024 PNG in as icon_1024.png and run this.
set -euo pipefail
cd "$(dirname "$0")"

[ -f icon_1024.png ] || { echo "Resources/icon_1024.png missing"; exit 1; }

SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -Z "$1" icon_1024.png --out "$SET/icon_$2.png" >/dev/null
done

iconutil -c icns "$SET" -o AppIcon.icns
echo "✓ Resources/AppIcon.icns"
