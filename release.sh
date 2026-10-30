#!/bin/sh
# Usage: ./release.sh 1.0.0
# Checks, builds a universal app, packages ClaudeWatch.dmg, and publishes it as GitHub release v<version>.
set -e
cd "$(dirname "$0")"
VERSION=${1:?usage: ./release.sh <version, e.g. 1.0.0>}
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first"; exit 1; }

./check.sh
VERSION=$VERSION UNIVERSAL=1 INSTALL=0 ./build.sh

# DMG with the app and an Applications shortcut, so users can drag to install
rm -rf dist && mkdir -p dist/dmg
cp -R ClaudeWatch.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "ClaudeWatch $VERSION" -srcfolder dist/dmg -format UDZO -ov dist/ClaudeWatch.dmg >/dev/null
rm -rf dist/dmg
shasum -a 256 dist/ClaudeWatch.dmg

git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" dist/ClaudeWatch.dmg --title "ClaudeWatch $VERSION" --notes "Download **ClaudeWatch.dmg** below, open it, and drag ClaudeWatch to Applications.

First launch: macOS will say it can't verify the developer (the app isn't notarized yet). Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only do this once.

Requires macOS 13 or newer. Works on Apple Silicon and Intel Macs."
echo "Released v$VERSION"
