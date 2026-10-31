#!/bin/bash
# Builds a signed, notarized Park.app and packages it as build/Park.zip for download.
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

# Hardened runtime and a secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --entitlements Resources/Park.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

ZIP=build/release/Park.zip
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "${1:-}" != "--skip-notarize" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  # Re-zip so the download carries the stapled ticket and opens offline.
  rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

shasum -a 256 "$ZIP"
echo "Ready: $ZIP"
