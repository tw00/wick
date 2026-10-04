#!/bin/bash
# Build (when this folder has a build.sh), sign with the Developer ID so the
# app opens on another Mac, and put the zip on mac.tw00.dev.
#
# Who can download is store.json the first time. Later publishes replace the
# zip and the screenshots and leave that list alone. Change it at
# https://os.tw00.dev/admin on the Mac apps tab.
#
# Screenshots: drop images in Resources/screenshots/, or leave
# assets/screenshot.png and this script picks it up.
set -euo pipefail
cd "$(dirname "$0")"

LIFEOS="${LIFEOS:-$HOME/Code/lifeos}"
FLY_TOML="$LIFEOS/services/hub/fly.toml"
SIGN_ID="Developer ID Application: TV Labs LTD (DR9WWQT8R8)"

[[ -f "$FLY_TOML" ]] || { echo "no fly.toml at $FLY_TOML" >&2; exit 1; }
[[ -f store.json ]] || { echo "store.json is missing. It says what the store page shows." >&2; exit 1; }

APP_REL="$(python3 -c 'import json;print(json.load(open("store.json")).get("app",""))')"
if [[ -n "$APP_REL" ]]; then
  SRC="$APP_REL"
  [[ -d "$SRC" ]] || { echo "store.json app not found: $SRC" >&2; exit 1; }
  NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$SRC/Contents/Info.plist")"
elif [[ -f Info.plist ]]; then
  NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Info.plist)"
  if [[ ! -d "build/$NAME.app" ]]; then
    ./build.sh
  fi
  SRC="build/$NAME.app"
else
  echo "no Info.plist and store.json has no \"app\"" >&2
  exit 1
fi

LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/pkg/shots"
cp -R "$SRC" "$STAGE/pkg/$NAME.app"

if security find-identity -v -p codesigning | grep -F -q "$SIGN_ID"; then
  echo "→ signing $NAME"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/pkg/$NAME.app"
else
  echo "warning: Developer ID is not in the keychain. Another Mac may refuse this zip." >&2
fi

echo "→ zipping"
ditto -c -k --keepParent "$STAGE/pkg/$NAME.app" "$STAGE/pkg/$NAME.zip"

ICON=""
for candidate in "$SRC/Contents/Resources/AppIcon.icns" "$SRC/Contents/Resources/iconfile.icns" "assets/icon.png"; do
  [[ -f "$candidate" ]] || continue
  ICON="$candidate"
  break
done
if [[ -n "$ICON" ]]; then
  sips -s format png -Z 512 "$ICON" --out "$STAGE/pkg/icon.png" >/dev/null
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || true)"
CATEGORY="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$SRC/Contents/Info.plist" 2>/dev/null || true)"
rm -rf "$STAGE/pkg/$NAME.app"

if [[ -d Resources/screenshots ]]; then
  i=0
  for f in Resources/screenshots/*; do
    [[ -f "$f" ]] || continue
    i=$((i + 1))
    ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
    cp "$f" "$STAGE/pkg/shots/$i.$ext"
  done
elif [[ -f assets/screenshot.png ]]; then
  cp assets/screenshot.png "$STAGE/pkg/shots/1.png"
fi

OLD="$(mktemp)"
fly ssh console --config "$FLY_TOML" -C "cat /data/mac-apps/$LOWER/app.json" >"$OLD" 2>/dev/null || true

STORE_VERSION="$VERSION" STORE_CATEGORY="$CATEGORY" python3 - "$STAGE/pkg/app.json" store.json "$NAME" "$LOWER" "$OLD" <<'PY'
import json, os, sys
out, store_path, name, lower, old_path = sys.argv[1:]
store = json.load(open(store_path))
shots = sorted(n for n in os.listdir(os.path.join(os.path.dirname(out), "shots")) if not n.startswith("."))
cats = {
    "public.app-category.business": "Business",
    "public.app-category.developer-tools": "Developer Tools",
    "public.app-category.education": "Education",
    "public.app-category.entertainment": "Entertainment",
    "public.app-category.finance": "Finance",
    "public.app-category.graphics-design": "Graphics & Design",
    "public.app-category.healthcare-fitness": "Health & Fitness",
    "public.app-category.lifestyle": "Lifestyle",
    "public.app-category.music": "Music",
    "public.app-category.news": "News",
    "public.app-category.photography": "Photo & Video",
    "public.app-category.productivity": "Productivity",
    "public.app-category.reference": "Reference",
    "public.app-category.social-networking": "Social",
    "public.app-category.sports": "Sports",
    "public.app-category.travel": "Travel",
    "public.app-category.utilities": "Utilities",
    "public.app-category.video": "Video",
    "public.app-category.weather": "Weather",
}
github = str(store.get("github") or "").strip()
category = str(store.get("category") or "").strip() or cats.get(os.environ.get("STORE_CATEGORY", ""), "")
version = str(store.get("version") or "").strip() or os.environ.get("STORE_VERSION", "")
app = {
    "id": lower,
    "title": name,
    "summary": store.get("summary", ""),
    "detail": store.get("detail", ""),
    "system": store.get("system", "macOS 14 or later, Apple silicon"),
    "accent": store.get("accent", "#d9a441"),
    "audience": store.get("audience", "signed-in"),
    "emails": [e.lower() for e in store.get("emails", [])],
    "zip": f"{name}.zip",
    "screenshots": shots,
    "github": github,
    "category": category,
    "version": version,
}
text = open(old_path, encoding="utf-8", errors="replace").read() if os.path.isfile(old_path) else ""
start = text.find("{")
if start >= 0:
    try:
        prev = json.loads(text[start:])
        if prev.get("audience") in ("public", "signed-in", "only"):
            app["audience"] = prev["audience"]
            app["emails"] = prev.get("emails") or []
        if not app["github"] and isinstance(prev.get("github"), str):
            app["github"] = prev["github"]
    except json.JSONDecodeError:
        pass
json.dump(app, open(out, "w"), indent=2)
print(app["audience"])
PY

echo "→ uploading to mac.tw00.dev"
fly ssh console --config "$FLY_TOML" -C "/bin/sh -c 'rm -rf /data/mac-apps/$LOWER && mkdir -p /data/mac-apps/$LOWER'"
COPYFILE_DISABLE=1 tar czf - --exclude='._*' --exclude='.DS_Store' --no-xattrs -C "$STAGE/pkg" . \
  | fly ssh console --config "$FLY_TOML" -C "/bin/sh -c 'tar xzf - -C /data/mac-apps/$LOWER'"
echo "✓ https://mac.tw00.dev/app/$LOWER"
