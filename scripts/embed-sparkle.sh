#!/bin/bash
# Copies Sparkle.framework into an app bundle and signs its parts, inside out, as Sparkle's docs say.
# Usage: scripts/embed-sparkle.sh <Park.app> <signing identity> [extra codesign flags...]
set -euo pipefail
APP="$1"; IDENTITY="$2"; shift 2
SRC=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
[ -d "$SRC" ] || { echo "Sparkle.framework not found; run swift build first." >&2; exit 1; }

mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SRC" "$APP/Contents/Frameworks/Sparkle.framework"

FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --sign "$IDENTITY" "$@")
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
