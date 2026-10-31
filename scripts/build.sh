#!/bin/bash
# Builds Park.app into ./build and (with --install) copies it to ~/Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Xcode's license isn't accepted on this Mac; the Command Line Tools toolchain works without it.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
CONFIG="${CONFIG:-release}"
# Signing: set PARK_SIGN_IDENTITY (or put it in scripts/signing.local, which is gitignored) to a
# certificate from `security find-identity -p codesigning`. A stable identity keeps macOS permissions
# across rebuilds; without one the app is signed ad hoc and asks for Accessibility again after each build.
[ -f scripts/signing.local ] && source scripts/signing.local
IDENTITY="${PARK_SIGN_IDENTITY:--}"

swift build -c "$CONFIG" --arch arm64

APP=build/Park.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/arm64-apple-macosx/$CONFIG/Park" "$APP/Contents/MacOS/Park"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Park 2>/dev/null || true
  rm -rf "$HOME/Applications/Park.app"
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/Park.app"
  open "$HOME/Applications/Park.app"
  echo "Installed and launched ~/Applications/Park.app"
fi
