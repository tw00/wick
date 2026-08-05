#!/bin/bash
# Compose the app icon from the mark, then build the .icns.
#
#   icon-mark.png   the artwork on transparency — just the burning ring
#   icon_1024.png   the composed icon: mark on a dark squircle tile
#   AppIcon.icns    what the app ships
#
# The tile is drawn here rather than baked into the artwork, so the mark can be
# redrawn without anyone having to match a background by hand. Apple's grid puts
# an 824 px tile inside a 1024 px canvas, and the corners are a superellipse
# rather than a rounded rectangle — circular corners read noticeably wrong next
# to real macOS icons.
#
# Every intermediate that takes part in a composite is forced to PNG32/sRGB. A
# greyscale layer anywhere in the chain drags the whole composite into greyscale
# and quietly turns the amber ring white.
set -euo pipefail
cd "$(dirname "$0")"

MARK=icon-mark.png
TILE=824          # tile size within the 1024 canvas
MARK_FRACTION=88  # percent of the tile the mark spans
SS=4              # supersampling for the squircle mask

[ -f "$MARK" ] || { echo "Resources/$MARK missing"; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# Superellipse |x|^n + |y|^n = 1, n = 5 — close enough to Apple's continuous
# corners at icon sizes, and smooth once supersampled down.
python3 - "$W/points.txt" "$((TILE * SS))" <<'PY'
import sys, math
out, size = sys.argv[1], int(sys.argv[2])
n, r, steps = 5.0, (size - 1) / 2.0, 720
pts = []
for i in range(steps):
    a = 2 * math.pi * i / steps
    c, s = math.cos(a), math.sin(a)
    x = math.copysign(abs(c) ** (2 / n), c)
    y = math.copysign(abs(s) ** (2 / n), s)
    pts.append(f"{r + r * x:.2f},{r + r * y:.2f}")
open(out, "w").write("polygon " + " ".join(pts))
PY

magick -size "$((TILE * SS))x$((TILE * SS))" xc:none -fill white \
    -draw "@$W/points.txt" -resize "${TILE}x${TILE}" "$W/mask.png"
magick "$W/mask.png" -alpha extract "$W/alpha.png"

# Matte charcoal, lit slightly from the top.
magick -size "${TILE}x${TILE}" gradient:'#33333A-#191919' "$W/grad.png"
magick "$W/grad.png" "$W/mask.png" -alpha off -compose CopyOpacity -composite \
    PNG32:"$W/tile.png"

# The mark, sized to the tile and centred on it.
MARK_PX=$((TILE * MARK_FRACTION / 100))
magick "$MARK" -resize "${MARK_PX}x${MARK_PX}" PNG32:"$W/mark.png"
magick PNG32:"$W/tile.png" PNG32:"$W/mark.png" -gravity center -compose Over -composite \
    PNG32:"$W/composed.png"

# A soft contact shadow under the tile, inside the 1024 canvas.
magick -size "${TILE}x${TILE}" xc:black "$W/alpha.png" -alpha off -compose CopyOpacity -composite \
    -channel A -evaluate multiply 0.35 +channel \
    -background none -gravity center -extent 1024x1024 -blur 0x18 -roll +0+14 \
    -colorspace sRGB PNG32:"$W/shadow.png"

magick PNG32:"$W/shadow.png" \
    \( PNG32:"$W/composed.png" -background none -gravity center -extent 1024x1024 \) \
    -compose Over -composite PNG32:icon_1024.png

SET="$W/AppIcon.iconset"
mkdir -p "$SET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -Z "$1" icon_1024.png --out "$SET/icon_$2.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns

echo "✓ Resources/icon_1024.png and AppIcon.icns"
