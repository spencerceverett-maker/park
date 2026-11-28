#!/bin/bash
# Ships a Park release: signed + notarized build, a GitHub release with Park.zip attached,
# and the website's Download button pointed at it. Run from the repo root:
#   scripts/publish.sh 1.0 [notes.html]
# The optional notes file is a short HTML fragment that Sparkle shows in the "update available" window.
# Needs: Developer ID identity, `park-notary` notarization profile, and gh signed in to the
# account that owns the repo (set GH_TOKEN, or `gh auth switch`).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/publish.sh <version> [notes.html]}"
NOTES_FILE="${2:-}"
REPO="spencerceverett-maker/park"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" Resources/Info.plist

scripts/release.sh

# The Sparkle feed. Installed copies of Park read it from the latest release (SUFeedURL), so it changes
# at the same moment as the download. Signed with the EdDSA key in the keychain (account "park").
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account park build/release/Park.zip)
NOTES="<p>Park $VERSION</p>"
[ -n "$NOTES_FILE" ] && NOTES=$(cat "$NOTES_FILE")
cat > build/release/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Park</title>
    <item>
      <title>Park $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Park.zip" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
APPCAST

# A stable link that always points at the newest release's download.
URL="https://github.com/$REPO/releases/latest/download/Park.dmg"
sed -i '' "s|DOWNLOAD_URL: [^,]*,|DOWNLOAD_URL: \"$URL\",|" site/main.js

git add Resources/Info.plist site/main.js
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

gh release create "v$VERSION" build/release/Park.dmg build/release/Park.zip build/release/appcast.xml --repo "$REPO" --title "Park $VERSION" \
  --notes "Signed and notarized by Apple. Open Park.dmg, drag Park into Applications, and open it from there. Requires macOS 14 or later. (Park.zip is the same app, for scripts and package managers.)"
echo "Released Park $VERSION: $URL"
