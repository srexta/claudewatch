#!/bin/sh
# Build ClaudeWatch.app. Env: VERSION (default 1.0.0), UNIVERSAL=1 for arm64+x86_64, INSTALL=0 to skip installing.
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-1.0.0}
APP=ClaudeWatch.app
BIN="$APP/Contents/MacOS/ClaudeWatch"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
if [ "$UNIVERSAL" = 1 ]; then
    for arch in arm64 x86_64; do
        swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos13.0 ClaudeWatch.swift -o "$BIN-$arch"
    done
    lipo -create "$BIN-arm64" "$BIN-x86_64" -output "$BIN"
    rm "$BIN-arm64" "$BIN-x86_64"
else
    swiftc -O -swift-version 5 -parse-as-library ClaudeWatch.swift -o "$BIN"
fi
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeWatch</string>
<key>CFBundleIdentifier</key><string>local.claudewatch</string>
<key>CFBundleName</key><string>ClaudeWatch</string>
<key>CFBundleDisplayName</key><string>ClaudeWatch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
# ponytail: ad-hoc signature (no Apple Developer ID); swap "-" for a Developer ID + notarize to remove the Gatekeeper prompt
codesign --force --sign - "$APP"
echo "Built $PWD/$APP ($VERSION)"

[ "$INSTALL" = 0 ] && exit 0
pkill -x ClaudeWatch || true
rm -rf /Applications/ClaudeWatch.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/ClaudeWatch.app
mdimport /Applications/ClaudeWatch.app
open /Applications/ClaudeWatch.app
echo "Installed /Applications/ClaudeWatch.app"
