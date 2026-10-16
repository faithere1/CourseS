#!/bin/bash
# Builds CourseS.app next to this script. Your data lives in
# ~/Library/Application Support/CourseS and is never touched by a rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="CourseS.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  src/main.swift -o "$APP/Contents/MacOS/CourseS" -framework Cocoa -framework WebKit

cp src/Info.plist "$APP/Contents/"
cp src/index.html "$APP/Contents/Resources/"

# App icon
swiftc -O src/icon.swift -o "$TMP/icon" -framework AppKit
"$TMP/icon" "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc signing skipped"
echo "Built $(pwd)/$APP"
