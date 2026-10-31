#!/bin/bash
# Builds a signed, notarized Park.app and packages it for download as build/release/Park.dmg
# (an art-directed drag-to-Applications window) and build/release/Park.zip.
#
# Needs, once per Mac:
#   - a "Developer ID Application" identity in the keychain (security find-identity -v -p codesigning)
#   - notarization credentials: xcrun notarytool store-credentials park-notary --apple-id <id> --team-id <team>
#
# Usage: scripts/release.sh [--skip-notarize]
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
IDENTITY="${PARK_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
PROFILE="${PARK_NOTARY_PROFILE:-park-notary}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the keychain." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
echo "Building Park $VERSION, signed by $IDENTITY"

# Universal binary, so it runs on Intel and Apple silicon. (Building both at once needs Xcode;
# the Command Line Tools build each architecture separately, then lipo merges them.)
SLICES=()
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH"
  SLICES+=("$(swift build -c release --arch "$ARCH" --show-bin-path)/Park")
done
BIN=build/release/Park-universal
mkdir -p build/release
lipo -create -output "$BIN" "${SLICES[@]}"

APP=build/release/Park.app
rm -rf "$APP" build/release/Park.zip && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Park"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Logo.png "$APP/Contents/Resources/Logo.png"

# Hardened runtime and a secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --entitlements Resources/Park.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

ZIP=build/release/Park.zip
ditto -c -k --keepParent "$APP" "$ZIP"

NOTARIZE=true
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=false

if $NOTARIZE; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  # Re-zip so the download carries the stapled ticket and opens offline.
  rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

# The disk image: the stapled app beside an Applications alias, over the quiet grid background drawn by
# scripts/dmg-quiet.swift. dmgbuild writes Finder's layout directly (no Finder scripting).
DMG=build/release/Park.dmg
VENV=build/.venv-dmg
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }
swift scripts/dmg-quiet.swift build/dmg >/dev/null
tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png -out build/dmg/background.tiff 2>/dev/null
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D background=build/dmg/background.tiff \
  -D icon=Resources/AppIcon.icns Park "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if $NOTARIZE; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG"
echo "Ready: $DMG and $ZIP"
