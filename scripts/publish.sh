#!/bin/bash
# Ships a Park release: signed + notarized build, a GitHub release with Park.zip attached,
# and the website's Download button pointed at it. Run from the repo root:
#   scripts/publish.sh 1.0
# Needs: Developer ID identity, `park-notary` notarization profile, and gh signed in to the
# account that owns the repo (set GH_TOKEN, or `gh auth switch`).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/publish.sh <version>}"
REPO="spencerceverett-maker/park"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" Resources/Info.plist

scripts/release.sh

# A stable link that always points at the newest release's download.
URL="https://github.com/$REPO/releases/latest/download/Park.dmg"
sed -i '' "s|DOWNLOAD_URL: [^,]*,|DOWNLOAD_URL: \"$URL\",|" site/main.js

git add Resources/Info.plist site/main.js
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

gh release create "v$VERSION" build/release/Park.dmg build/release/Park.zip --repo "$REPO" --title "Park $VERSION" \
  --notes "Signed and notarized by Apple. Open Park.dmg, drag Park into Applications, and open it from there. Requires macOS 14 or later. (Park.zip is the same app, for scripts and package managers.)"
echo "Released Park $VERSION: $URL"
