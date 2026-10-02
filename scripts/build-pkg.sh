#!/bin/bash
# Builds dist/HorseBar-<version>.pkg — an installer you can send to other people.
#   --public   leave out sounds-private/ (for the GitHub release)
set -euo pipefail
export COPYFILE_DISABLE=1   # no ._ AppleDouble files in the payload
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/scripts/pkg"
WORK="$ROOT/SlapMac/.build/pkg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/SlapMac/Resources/Info.plist")

cd "$ROOT/SlapMac"
swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$WORK" && mkdir -p "$WORK"
STAGE="$WORK/root"

# app bundle
APP="$STAGE/Applications/HorseBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"
cp "$BIN/HorseBar" "$APP/Contents/MacOS/HorseBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
SOUND_DIRS=("$ROOT/sounds")
if [ "${1:-}" != "--public" ] && [ -d "$ROOT/sounds-private" ]; then
    SOUND_DIRS+=("$ROOT/sounds-private")
fi
find "${SOUND_DIRS[@]}" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aif*' -o -iname '*.caf' \) \
    -exec cp {} "$APP/Contents/Resources/Sounds/" \;
swift "$PKG/make-icon.swift" "$WORK/AppIcon.iconset" 2>/dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE"   # drop quarantine/provenance attrs from downloaded sounds
codesign --force --sign - "$APP"

# background service
mkdir -p "$STAGE/Library/Application Support/HorseBar" "$STAGE/Library/LaunchDaemons"
cp "$BIN/slapd" "$STAGE/Library/Application Support/HorseBar/slapd"
codesign --force --sign - "$STAGE/Library/Application Support/HorseBar/slapd"
cp Resources/com.theglanda.slapd.plist "$STAGE/Library/LaunchDaemons/"

# always install to /Applications, even if a copy of the app exists elsewhere
pkgbuild --analyze --root "$STAGE" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"

pkgbuild --root "$STAGE" --component-plist "$WORK/component.plist" \
    --scripts "$PKG/scripts" --identifier com.theglanda.horsebar.pkg \
    --version "$VERSION" --install-location / "$WORK/horsebar-component.pkg"

sed "s/__VERSION__/$VERSION/" "$PKG/distribution.xml" > "$WORK/distribution.xml"
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/HorseBar-$VERSION.pkg"
productbuild --distribution "$WORK/distribution.xml" --resources "$PKG/resources" \
    --package-path "$WORK" "$OUT"

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
